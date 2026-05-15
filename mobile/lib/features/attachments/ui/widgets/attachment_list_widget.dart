import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/models/attachment_models.dart';
import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../bloc/attachment_cubit.dart';
import '../image_viewer_screen.dart';
import '../video_player_screen.dart';

/// Attachment section displayed inside the task detail screen (M-026).
///
/// Shows:
/// - Upload progress bar during Pattern A flow
/// - Grid of attachment thumbnails
/// - FAB-style add button (disabled when offline or uploading)
class AttachmentListWidget extends StatefulWidget {
  const AttachmentListWidget({super.key, required this.taskId});

  final String taskId;

  @override
  State<AttachmentListWidget> createState() => _AttachmentListWidgetState();
}

class _AttachmentListWidgetState extends State<AttachmentListWidget> {
  @override
  void initState() {
    super.initState();
    context.read<AttachmentCubit>().loadAttachments();
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = context.select<ConnectivityCubit, bool>(
      (c) => c.state == ConnectivityStatus.disconnected,
    );

    return BlocConsumer<AttachmentCubit, AttachmentState>(
      listener: (context, state) {
        if (state is AttachmentError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final attachments = switch (state) {
          AttachmentIdle(attachments: final a) => a,
          AttachmentError(attachments: final a) => a,
          UploadPicking(attachments: final a) => a,
          UploadPreRegistering(attachments: final a) => a,
          UploadingToS3(attachments: final a) => a,
          UploadConfirming(attachments: final a) => a,
          UploadComplete(attachments: final a) => a,
          AttachmentLoading() => const <Attachment>[],
        };

        final isUploading = state is UploadPreRegistering ||
            state is UploadingToS3 ||
            state is UploadConfirming;

        final uploadProgress = state is UploadingToS3 ? state.progress : null;
        final isLoading = state is AttachmentLoading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with add button
            _buildHeader(context, isOffline, isUploading, isLoading),
            const SizedBox(height: 8),

            // Upload progress bar
            if (uploadProgress != null) ...[
              LinearProgressIndicator(
                key: const Key('attachment_upload_progress'),
                value: uploadProgress,
              ),
              const SizedBox(height: 6),
              Text(
                'Uploading… ${(uploadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ] else if (isUploading) ...[
              const LinearProgressIndicator(
                key: Key('attachment_upload_indeterminate'),
              ),
              const SizedBox(height: 8),
            ],

            // Loading shimmer or content
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (attachments.isEmpty)
              _EmptyAttachmentsPlaceholder(isOffline: isOffline)
            else
              _AttachmentGrid(attachments: attachments, taskId: widget.taskId),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isOffline,
    bool isUploading,
    bool isLoading,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Attachments',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Tooltip(
          message: isOffline
              ? "You're offline"
              : isUploading
                  ? 'Upload in progress'
                  : 'Add attachment',
          child: TextButton.icon(
            key: const Key('attachment_add_button'),
            icon: const Icon(Icons.attach_file_rounded, size: 16),
            label: const Text('Add'),
            onPressed: (isOffline || isUploading || isLoading)
                ? null
                : () => _showPickerSheet(context),
          ),
        ),
      ],
    );
  }

  void _showPickerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('attachment_pick_camera'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo / Video'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context
                    .read<AttachmentCubit>()
                    .pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              key: const Key('attachment_pick_gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context
                    .read<AttachmentCubit>()
                    .pickAndUpload(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid ──────────────────────────────────────────────────────────────────────

class _AttachmentGrid extends StatelessWidget {
  const _AttachmentGrid({
    required this.attachments,
    required this.taskId,
  });

  final List<Attachment> attachments;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, i) =>
          _AttachmentTile(attachment: attachments[i], taskId: taskId),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.taskId});

  final Attachment attachment;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('attachment_tile_${attachment.id}'),
      direction: DismissDirection.up,
      background: Container(
        color: Colors.red.withOpacity(0.8),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 8),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _scheduleDelete(context),
      child: GestureDetector(
        onTap: () => _openViewer(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: attachment.isImage
              ? _ImageThumbnail(attachment: attachment, taskId: taskId)
              : _VideoThumbnail(attachment: attachment),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Attachment?'),
        content: Text('"${attachment.filename}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _scheduleDelete(BuildContext context) {
    final cubit = context.read<AttachmentCubit>();
    cubit.scheduleDelete(attachment.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Attachment removed'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => cubit.cancelDelete(attachment.id),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openViewer(BuildContext context) async {
    final cubit = context.read<AttachmentCubit>();
    final url = await cubit.getDownloadUrl(attachment.id);
    if (url == null || !context.mounted) return;

    if (attachment.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerScreen(
            url: url,
            filename: attachment.filename,
          ),
        ),
      );
    } else if (attachment.isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            url: url,
            filename: attachment.filename,
          ),
        ),
      );
    }
  }
}

// ── Thumbnail widgets ─────────────────────────────────────────────────────────

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.attachment, required this.taskId});
  final Attachment attachment;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: context.read<AttachmentCubit>().getDownloadUrl(attachment.id),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) {
          return _placeholder(Icons.image_outlined);
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(Icons.image_outlined),
          errorWidget: (_, __, ___) => _placeholder(Icons.broken_image_outlined),
        );
      },
    );
  }

  Widget _placeholder(IconData icon) => Container(
        color: Colors.grey.shade200,
        child: Center(
          child: Icon(icon, color: Colors.grey.shade500),
        ),
      );
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.play_circle_outline_rounded,
              color: Colors.white, size: 36),
          Positioned(
            bottom: 4,
            left: 4,
            child: Text(
              attachment.formattedSize,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty placeholder ─────────────────────────────────────────────────────────

class _EmptyAttachmentsPlaceholder extends StatelessWidget {
  const _EmptyAttachmentsPlaceholder({required this.isOffline});
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.attach_file_rounded,
              size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            isOffline ? 'Attachments unavailable offline' : 'No attachments yet',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
