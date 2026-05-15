import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/attachment_models.dart';
import 'package:task_nibbles/core/connectivity/connectivity_cubit.dart';
import 'package:task_nibbles/features/attachments/bloc/attachment_cubit.dart';
import 'package:task_nibbles/features/attachments/ui/widgets/attachment_list_widget.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockAttachmentCubit extends MockCubit<AttachmentState>
    implements AttachmentCubit {}

class MockConnectivityCubit extends MockCubit<ConnectivityStatus>
    implements ConnectivityCubit {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Attachment _makeAttachment(String id) => Attachment(
      id: id,
      taskId: 'task-1',
      filename: 'photo.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 512000,
      createdAt: DateTime(2026, 5, 15),
      confirmedAt: DateTime(2026, 5, 15),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockAttachmentCubit mockCubit;
  late MockConnectivityCubit mockConnectivity;

  setUp(() {
    mockCubit = MockAttachmentCubit();
    mockConnectivity = MockConnectivityCubit();
    when(() => mockConnectivity.state).thenReturn(ConnectivityStatus.connected);
    // loadAttachments stub
    when(() => mockCubit.loadAttachments()).thenAnswer((_) async {});
  });

  Widget buildSubject({required AttachmentState state}) {
    when(() => mockCubit.state).thenReturn(state);
    return MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<AttachmentCubit>.value(value: mockCubit),
            BlocProvider<ConnectivityCubit>.value(value: mockConnectivity),
          ],
          child: const AttachmentListWidget(taskId: 'task-1'),
        ),
      ),
    );
  }

  // ── Test: thumbnail visible for image attachment ────────────────────────────

  testWidgets(
    'shows attachment tile for an image attachment',
    (tester) async {
      when(() => mockCubit.getDownloadUrl(any())).thenAnswer(
        (_) async => 'https://example.com/photo.jpg',
      );
      await tester.pumpWidget(buildSubject(
        state: AttachmentIdle(attachments: [_makeAttachment('att-1')]),
      ));
      await tester.pump();

      // Grid tile is rendered with the dismissible key.
      expect(find.byKey(const Key('attachment_tile_att-1')), findsOneWidget);
    },
  );

  // ── Test: add button disabled when offline ─────────────────────────────────

  testWidgets(
    'add button is disabled (null onPressed) when offline',
    (tester) async {
      when(() => mockConnectivity.state)
          .thenReturn(ConnectivityStatus.disconnected);

      await tester.pumpWidget(buildSubject(
        state: const AttachmentIdle(attachments: []),
      ));
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.byKey(const Key('attachment_add_button')),
      );
      expect(button.onPressed, isNull,
          reason: 'Add button must be disabled when offline');
    },
  );

  // ── Test: progress bar visible during upload ────────────────────────────────

  testWidgets(
    'upload progress bar is visible during UploadingToS3',
    (tester) async {
      await tester.pumpWidget(buildSubject(
        state: const UploadingToS3(progress: 0.45, attachments: []),
      ));
      await tester.pump();

      expect(
        find.byKey(const Key('attachment_upload_progress')),
        findsOneWidget,
      );
    },
  );
}
