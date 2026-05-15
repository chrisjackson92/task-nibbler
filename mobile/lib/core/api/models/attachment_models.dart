import 'package:equatable/equatable.dart';

// ──────────────────────────────────────────────
// Attachment entity (CON-002 §4 list response)
// ──────────────────────────────────────────────

class Attachment extends Equatable {
  const Attachment({
    required this.id,
    required this.taskId,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.confirmedAt,
  });

  final String id;
  final String taskId;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime confirmedAt;

  /// True when this is an image MIME type the UI can preview.
  bool get isImage =>
      mimeType == 'image/jpeg' ||
      mimeType == 'image/png' ||
      mimeType == 'image/heic' ||
      mimeType == 'image/webp';

  /// True when this is a video MIME type.
  bool get isVideo =>
      mimeType == 'video/mp4' || mimeType == 'video/quicktime';

  /// Human-readable file size (e.g. "2.4 MB").
  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        filename: json['filename'] as String,
        mimeType: json['mime_type'] as String,
        sizeBytes: json['size_bytes'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, taskId, filename, mimeType, sizeBytes, createdAt, confirmedAt];
}

// ──────────────────────────────────────────────
// Request & response models
// ──────────────────────────────────────────────

/// Request body for `POST /tasks/:id/attachments` (pre-register).
class PreRegisterRequest {
  const PreRegisterRequest({
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String filename;
  final String mimeType;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
      };
}

/// Response from `POST /tasks/:id/attachments` (pre-register).
class PreRegisterResponse extends Equatable {
  const PreRegisterResponse({
    required this.attachmentId,
    required this.uploadUrl,
    required this.expiresAt,
  });

  final String attachmentId;
  final String uploadUrl;
  final DateTime expiresAt;

  factory PreRegisterResponse.fromJson(Map<String, dynamic> json) =>
      PreRegisterResponse(
        attachmentId: json['attachment_id'] as String,
        uploadUrl: json['upload_url'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  @override
  List<Object?> get props => [attachmentId, uploadUrl, expiresAt];
}

/// Response from `GET /tasks/:id/attachments`.
class AttachmentListResponse extends Equatable {
  const AttachmentListResponse({required this.data});

  final List<Attachment> data;

  factory AttachmentListResponse.fromJson(Map<String, dynamic> json) =>
      AttachmentListResponse(
        data: (json['data'] as List<dynamic>)
            .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [data];
}

/// Response from `GET /tasks/:id/attachments/:aid/url`.
class AttachmentUrlResponse extends Equatable {
  const AttachmentUrlResponse({
    required this.url,
    required this.expiresAt,
  });

  final String url;
  final DateTime expiresAt;

  factory AttachmentUrlResponse.fromJson(Map<String, dynamic> json) =>
      AttachmentUrlResponse(
        url: json['url'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  @override
  List<Object?> get props => [url, expiresAt];
}

// ──────────────────────────────────────────────
// MIME allowlist constant (mirrors BE validation)
// ──────────────────────────────────────────────

/// Accepted MIME types (PRJ-001 §5.3).
const Set<String> kAllowedMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/webp',
  'video/mp4',
  'video/quicktime',
};

/// Maps file extension → MIME type for the image_picker path.
String? mimeTypeForExtension(String ext) => switch (ext.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      _ => null,
    };
