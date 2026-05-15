import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/models/attachment_models.dart';
import '../data/attachment_repository.dart';

// ──────────────────────────────────────────────
// Upload state machine (SPR-003-MB spec)
// ──────────────────────────────────────────────

sealed class AttachmentState extends Equatable {
  const AttachmentState();

  @override
  List<Object?> get props => [];
}

/// Initial state — shows the attachment list.
class AttachmentIdle extends AttachmentState {
  const AttachmentIdle({required this.attachments});
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [attachments];
}

class AttachmentLoading extends AttachmentState {
  const AttachmentLoading();
}

class AttachmentError extends AttachmentState {
  const AttachmentError(this.message, {this.attachments = const []});
  final String message;
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [message, attachments];
}

/// User has opened the picker but not yet selected a file.
class UploadPicking extends AttachmentState {
  const UploadPicking({required this.attachments});
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [attachments];
}

/// POSTing to /api/v1/tasks/:id/attachments to pre-register.
class UploadPreRegistering extends AttachmentState {
  const UploadPreRegistering({required this.attachments});
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [attachments];
}

/// PUTting to S3 — [progress] is 0.0 – 1.0.
class UploadingToS3 extends AttachmentState {
  const UploadingToS3({required this.progress, required this.attachments});
  final double progress;
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [progress, attachments];
}

/// POSTing confirm to the API.
class UploadConfirming extends AttachmentState {
  const UploadConfirming({required this.attachments});
  final List<Attachment> attachments;

  @override
  List<Object?> get props => [attachments];
}

/// Full Pattern A cycle completed.
class UploadComplete extends AttachmentState {
  const UploadComplete({required this.attachments, required this.newAttachment});
  final List<Attachment> attachments;
  final Attachment newAttachment;

  @override
  List<Object?> get props => [attachments, newAttachment];
}

// ──────────────────────────────────────────────
// Cubit
// ──────────────────────────────────────────────

/// Injectable permission check — defaults to real [Permission.request].
/// Override in tests to avoid platform-channel calls.
typedef PermissionChecker = Future<bool> Function(ImageSource source);

Future<bool> _defaultPermissionChecker(ImageSource source) async {
  final permission =
      source == ImageSource.camera ? Permission.camera : Permission.photos;
  final status = await permission.request();
  return !status.isDenied && !status.isPermanentlyDenied;
}

/// Manages attachment list + Pattern A upload flow for a single task.
///
/// Lifecycle:
///   loadAttachments() → [AttachmentIdle]
///   pickAndUpload()   → Picking → PreRegistering → UploadingToS3 → Confirming → Complete
///   deleteAttachment() → 3-second undo window → API DELETE → [AttachmentIdle]
class AttachmentCubit extends Cubit<AttachmentState> {
  AttachmentCubit({
    required this.taskId,
    required this.repository,
    ImagePicker? picker,
    PermissionChecker? permissionChecker,
  })  : _picker = picker ?? ImagePicker(),
        _permissionChecker = permissionChecker ?? _defaultPermissionChecker,
        super(const AttachmentLoading());

  final String taskId;
  final AttachmentRepository repository;
  final ImagePicker _picker;
  final PermissionChecker _permissionChecker;

  /// Active undo timer — cancelled if user taps UNDO.
  Timer? _deleteTimer;

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> loadAttachments() async {
    emit(const AttachmentLoading());
    try {
      final attachments = await repository.listAttachments(taskId);
      emit(AttachmentIdle(attachments: attachments));
    } on AttachmentRepositoryException catch (e) {
      emit(AttachmentError(e.message));
    } catch (_) {
      emit(const AttachmentError('Failed to load attachments.'));
    }
  }

  // ── Upload — Pattern A ─────────────────────────────────────────────────────

  /// Full upload flow: pick → pre-register → S3 PUT → confirm.
  Future<void> pickAndUpload(ImageSource source) async {
    final current = _currentAttachments();

    // ── Step 0: Permission ────────────────────────────────────────────────────
    final granted = await _permissionChecker(source);
    if (!granted) {
      emit(AttachmentError(
        'Permission denied. Please allow access in Settings.',
        attachments: current,
      ));
      return;
    }

    // ── Step 1: Pick file ─────────────────────────────────────────────────────
    emit(UploadPicking(attachments: current));
    XFile? picked;
    try {
      picked = await _picker.pickMedia();
    } catch (_) {
      emit(AttachmentIdle(attachments: current));
      return;
    }
    if (picked == null) {
      emit(AttachmentIdle(attachments: current));
      return;
    }

    final file = File(picked.path);
    final ext = picked.name.split('.').last;
    final mimeType = mimeTypeForExtension(ext) ?? 'application/octet-stream';
    final sizeBytes = await file.length();

    // ── Step 2: Pre-register ──────────────────────────────────────────────────
    emit(UploadPreRegistering(attachments: current));
    PreRegisterResponse preReg;
    try {
      preReg = await repository.preRegister(
        taskId: taskId,
        filename: picked.name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
      );
    } on AttachmentRepositoryException catch (e) {
      emit(AttachmentError(e.message, attachments: current));
      return;
    }

    // ── Step 3: Upload to S3 ─────────────────────────────────────────────────
    emit(UploadingToS3(progress: 0, attachments: current));
    try {
      await repository.uploadToS3(
        uploadUrl: preReg.uploadUrl,
        file: file,
        mimeType: mimeType,
        onProgress: (p) {
          if (!isClosed) emit(UploadingToS3(progress: p, attachments: current));
        },
      );
    } on AttachmentRepositoryException catch (e) {
      emit(AttachmentError(e.message, attachments: current));
      return;
    }

    // ── Step 4: Confirm ───────────────────────────────────────────────────────
    emit(UploadConfirming(attachments: current));
    try {
      await repository.confirm(taskId, preReg.attachmentId);
    } on AttachmentRepositoryException catch (e) {
      emit(AttachmentError(e.message, attachments: current));
      return;
    }

    // Refresh list to get the confirmed Attachment entity.
    await loadAttachments();
  }

  // ── Delete (with undo) ─────────────────────────────────────────────────────

  /// Optimistically removes the attachment from the list and starts a 3-second
  /// timer. If [cancelDelete] is called before the timer fires, no API call
  /// is made.
  void scheduleDelete(String attachmentId) {
    final current = _currentAttachments();
    final updated = current.where((a) => a.id != attachmentId).toList();
    emit(AttachmentIdle(attachments: updated));

    _deleteTimer?.cancel();
    _deleteTimer = Timer(const Duration(seconds: 3), () {
      _commitDelete(attachmentId, updated);
    });
  }

  /// Cancels a pending delete (called when user taps UNDO in snackbar).
  void cancelDelete(String attachmentId) {
    _deleteTimer?.cancel();
    _deleteTimer = null;
    // Restore — reload from API for accuracy.
    loadAttachments();
  }

  Future<void> _commitDelete(
    String attachmentId,
    List<Attachment> optimisticList,
  ) async {
    try {
      await repository.deleteAttachment(taskId, attachmentId);
      // Already removed from UI — nothing to do.
    } on AttachmentRepositoryException catch (e) {
      // Restore list on failure.
      emit(AttachmentError(e.message, attachments: optimisticList));
    }
  }

  // ── Get fresh download URL ─────────────────────────────────────────────────

  /// Fetches a fresh presigned URL — never stored in state per CON-002 §4.
  Future<String?> getDownloadUrl(String attachmentId) async {
    try {
      return await repository.getDownloadUrl(taskId, attachmentId);
    } on AttachmentRepositoryException {
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Attachment> _currentAttachments() {
    final s = state;
    return switch (s) {
      AttachmentIdle(attachments: final a) => a,
      AttachmentError(attachments: final a) => a,
      UploadPicking(attachments: final a) => a,
      UploadPreRegistering(attachments: final a) => a,
      UploadingToS3(attachments: final a) => a,
      UploadConfirming(attachments: final a) => a,
      UploadComplete(attachments: final a) => a,
      AttachmentLoading() => const [],
    };
  }

  @override
  Future<void> close() {
    _deleteTimer?.cancel();
    return super.close();
  }
}
