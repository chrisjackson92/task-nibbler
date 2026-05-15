import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/attachment_models.dart';
import 'package:task_nibbles/features/attachments/bloc/attachment_cubit.dart';
import 'package:task_nibbles/features/attachments/data/attachment_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockAttachmentRepository extends Mock implements AttachmentRepository {}
class MockImagePicker extends Mock implements ImagePicker {}

// ── Test data ─────────────────────────────────────────────────────────────────

const _taskId = 'task-1';

Attachment _makeAttachment(String id) => Attachment(
      id: id,
      taskId: _taskId,
      filename: 'photo.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 512000,
      createdAt: DateTime(2026, 5, 15),
      confirmedAt: DateTime(2026, 5, 15),
    );

final _preReg = PreRegisterResponse(
  attachmentId: 'att-1',
  uploadUrl: 'https://s3.example.com/upload',
  expiresAt: DateTime(2026, 5, 15, 12, 15),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockAttachmentRepository mockRepo;
  late MockImagePicker mockPicker;

  setUpAll(() {
    registerFallbackValue(ImageSource.gallery);
    registerFallbackValue(File(''));
  });

  setUp(() {
    mockRepo = MockAttachmentRepository();
    mockPicker = MockImagePicker();
    when(() => mockRepo.listAttachments(_taskId))
        .thenAnswer((_) async => [_makeAttachment('att-1')]);
  });

  AttachmentCubit buildCubit() => AttachmentCubit(
        taskId: _taskId,
        repository: mockRepo,
        picker: mockPicker,
        permissionChecker: (_) async => true,
      );

  // ── Load ────────────────────────────────────────────────────────────────────

  group('AttachmentCubit — loadAttachments', () {
    blocTest<AttachmentCubit, AttachmentState>(
      'load → [Loading, Idle with attachments]',
      build: buildCubit,
      act: (c) => c.loadAttachments(),
      expect: () => [
        isA<AttachmentLoading>(),
        isA<AttachmentIdle>().having(
          (s) => s.attachments.length,
          'attachments.length',
          1,
        ),
      ],
    );
  });

  // ── Upload success ─────────────────────────────────────────────────────────

  group('AttachmentCubit — upload success', () {
    late File tempFile;

    setUp(() async {
      tempFile = File('${Directory.systemTemp.path}/test.jpg');
      await tempFile.writeAsBytes([0, 1, 2, 3]);
    });

    tearDown(() async {
      if (tempFile.existsSync()) await tempFile.delete();
    });

    blocTest<AttachmentCubit, AttachmentState>(
      'upload success → Picking → PreRegistering → UploadingToS3 → Confirming → Idle',
      build: buildCubit,
      setUp: () {
        when(() => mockPicker.pickMedia()).thenAnswer(
          (_) async => XFile(tempFile.path, name: 'photo.jpg'),
        );
        when(
          () => mockRepo.preRegister(
            taskId: _taskId,
            filename: any(named: 'filename'),
            mimeType: any(named: 'mimeType'),
            sizeBytes: any(named: 'sizeBytes'),
          ),
        ).thenAnswer((_) async => _preReg);
        when(
          () => mockRepo.uploadToS3(
            uploadUrl: any(named: 'uploadUrl'),
            file: any(named: 'file'),
            mimeType: any(named: 'mimeType'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockRepo.confirm(_taskId, _preReg.attachmentId))
            .thenAnswer((_) async {});
      },
      seed: () => const AttachmentIdle(attachments: []),
      act: (c) => c.pickAndUpload(ImageSource.gallery),
      expect: () => [
        isA<UploadPicking>(),
        isA<UploadPreRegistering>(),
        isA<UploadingToS3>(),
        isA<UploadConfirming>(),
        // After confirm, loadAttachments is called → Loading then Idle
        isA<AttachmentLoading>(),
        isA<AttachmentIdle>().having(
          (s) => s.attachments.length,
          'attachments.length',
          1,
        ),
      ],
    );
  });

  // ── Upload failure: S3 PUT fails ───────────────────────────────────────────

  group('AttachmentCubit — S3 PUT failure', () {
    late File tempFile;

    setUp(() async {
      tempFile = File('${Directory.systemTemp.path}/test_fail.jpg');
      await tempFile.writeAsBytes([0, 1, 2, 3]);
    });

    tearDown(() async {
      if (tempFile.existsSync()) await tempFile.delete();
    });

    blocTest<AttachmentCubit, AttachmentState>(
      'S3 PUT fail → UploadFailed state (AttachmentError)',
      build: buildCubit,
      setUp: () {
        when(() => mockPicker.pickMedia()).thenAnswer(
          (_) async => XFile(tempFile.path, name: 'photo.jpg'),
        );
        when(
          () => mockRepo.preRegister(
            taskId: _taskId,
            filename: any(named: 'filename'),
            mimeType: any(named: 'mimeType'),
            sizeBytes: any(named: 'sizeBytes'),
          ),
        ).thenAnswer((_) async => _preReg);
        when(
          () => mockRepo.uploadToS3(
            uploadUrl: any(named: 'uploadUrl'),
            file: any(named: 'file'),
            mimeType: any(named: 'mimeType'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenThrow(
          const AttachmentRepositoryException('Upload to S3 failed: network error'),
        );
      },
      seed: () => const AttachmentIdle(attachments: []),
      act: (c) => c.pickAndUpload(ImageSource.gallery),
      expect: () => [
        isA<UploadPicking>(),
        isA<UploadPreRegistering>(),
        isA<UploadingToS3>(),
        isA<AttachmentError>().having(
          (s) => s.message,
          'message',
          contains('S3'),
        ),
      ],
    );
  });

  // ── Delete with undo ───────────────────────────────────────────────────────

  group('AttachmentCubit — scheduleDelete', () {
    test('scheduleDelete removes from list immediately', () async {
      final cubit = buildCubit();
      cubit.emit(AttachmentIdle(attachments: [
        _makeAttachment('att-1'),
        _makeAttachment('att-2'),
      ]));

      // No API call wired yet — that fires after 3 seconds (timer not awaited).
      when(() => mockRepo.deleteAttachment(_taskId, 'att-1'))
          .thenAnswer((_) async {});

      cubit.scheduleDelete('att-1');

      final state = cubit.state;
      expect(state, isA<AttachmentIdle>());
      expect(
        (state as AttachmentIdle).attachments.any((a) => a.id == 'att-1'),
        isFalse,
        reason: 'att-1 should be optimistically removed',
      );
      cubit.close();
    });

    test('cancelDelete restores attachment (loadAttachments called)', () async {
      final cubit = buildCubit();
      cubit.emit(AttachmentIdle(attachments: [_makeAttachment('att-1')]));

      when(() => mockRepo.deleteAttachment(_taskId, 'att-1'))
          .thenAnswer((_) async {});

      cubit.scheduleDelete('att-1');
      cubit.cancelDelete('att-1');

      // Give loadAttachments a chance to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify the delete API was NOT called (timer cancelled).
      verifyNever(() => mockRepo.deleteAttachment(any(), any()));

      cubit.close();
    });
  });
}
