import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/models/attachment_models.dart';

/// Repository wrapping all attachment API routes (CON-002 §4) plus
/// the direct S3 PUT for Pattern A upload.
///
/// CRITICAL: S3 uploads use [_s3Dio] — a plain Dio with NO interceptors.
/// Sending `Authorization: Bearer` to S3 presigned URLs causes a 403.
class AttachmentRepository {
  AttachmentRepository({required this.apiDio}) : _s3Dio = Dio();

  /// Authenticated Dio for Task Nibbles API calls.
  final Dio apiDio;

  /// Plain Dio (no interceptors) used exclusively for S3 PUT uploads.
  final Dio _s3Dio;

  static const _maxFileSizeBytes = 200 * 1024 * 1024; // 200 MiB

  // ── Read ───────────────────────────────────────────────────────────────────

  /// GET /tasks/:taskId/attachments — list completed attachments.
  Future<List<Attachment>> listAttachments(String taskId) async {
    try {
      final response = await apiDio.get<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/attachments',
      );
      return AttachmentListResponse.fromJson(response.data!).data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /tasks/:taskId/attachments/:aid/url — fresh presigned download URL.
  ///
  /// Must NOT be cached — the URL is valid for 60 min and must never be stored
  /// in persistent state per CON-002 §4 spec note.
  Future<String> getDownloadUrl(String taskId, String attachmentId) async {
    try {
      final response = await apiDio.get<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/attachments/$attachmentId/url',
      );
      return AttachmentUrlResponse.fromJson(response.data!).url;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Pattern A Upload ────────────────────────────────────────────────────────

  /// Step 1 — POST /tasks/:taskId/attachments — pre-register the attachment.
  /// Returns the presigned S3 PUT URL and the server-assigned attachment ID.
  Future<PreRegisterResponse> preRegister({
    required String taskId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    if (!kAllowedMimeTypes.contains(mimeType)) {
      throw const AttachmentRepositoryException(
        'File type not supported. Use JPEG, PNG, HEIC, MP4, or MOV.',
      );
    }
    if (sizeBytes > _maxFileSizeBytes) {
      throw const AttachmentRepositoryException(
        'File is too large. Maximum size is 200 MB.',
      );
    }
    try {
      final response = await apiDio.post<Map<String, dynamic>>(
        '/api/v1/tasks/$taskId/attachments',
        data: PreRegisterRequest(
          filename: filename,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
        ).toJson(),
      );
      return PreRegisterResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Step 2 — PUT to the presigned S3 URL directly.
  ///
  /// [onProgress] receives `sent / total` fraction for the progress bar.
  /// Uses [_s3Dio] (no Authorization header) to avoid S3 rejecting the JWT.
  Future<void> uploadToS3({
    required String uploadUrl,
    required File file,
    required String mimeType,
    required void Function(double) onProgress,
  }) async {
    final sizeBytes = await file.length();
    try {
      await _s3Dio.put<void>(
        uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            HttpHeaders.contentTypeHeader: mimeType,
            HttpHeaders.contentLengthHeader: sizeBytes,
          },
        ),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress(sent / total);
        },
      );
    } on DioException catch (e) {
      throw AttachmentRepositoryException(
        'Upload to S3 failed: ${e.message ?? 'unknown error'}',
      );
    }
  }

  /// Step 3 — POST /tasks/:taskId/attachments/:aid/confirm
  Future<void> confirm(String taskId, String attachmentId) async {
    try {
      await apiDio.post<void>(
        '/api/v1/tasks/$taskId/attachments/$attachmentId/confirm',
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// DELETE /tasks/:taskId/attachments/:aid
  Future<void> deleteAttachment(String taskId, String attachmentId) async {
    try {
      await apiDio.delete<void>(
        '/api/v1/tasks/$taskId/attachments/$attachmentId',
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  Exception _mapError(DioException e) {
    String? code;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>? ?? data;
      code = err['code'] as String?;
    }
    return switch (code) {
      'TASK_NOT_FOUND' => const AttachmentRepositoryException('Task not found.'),
      'ATTACHMENT_NOT_FOUND' =>
        const AttachmentRepositoryException('Attachment not found.'),
      'ATTACHMENT_LIMIT' => const AttachmentRepositoryException(
          'Maximum 10 attachments per task.',
        ),
      'FILE_TOO_LARGE' => const AttachmentRepositoryException(
          'File exceeds the 200 MB limit.',
        ),
      'INVALID_MIME_TYPE' => const AttachmentRepositoryException(
          'File type not supported.',
        ),
      'ATTACHMENT_NOT_PENDING' => const AttachmentRepositoryException(
          'Attachment is in an unexpected state.',
        ),
      _ => AttachmentRepositoryException(
          e.message ?? 'An unexpected error occurred.',
        ),
    };
  }
}

/// Typed exception from [AttachmentRepository].
class AttachmentRepositoryException implements Exception {
  const AttachmentRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the user denies media permissions.
class AttachmentPermissionDenied implements Exception {
  const AttachmentPermissionDenied();

  @override
  String toString() => 'Media permission denied. Please allow access in Settings.';
}
