import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/task_models.dart';
import 'package:task_nibbles/core/connectivity/connectivity_cubit.dart';
import 'package:task_nibbles/features/gamification/bloc/gamification_cubit.dart';
import 'package:task_nibbles/features/tasks/bloc/task_list_bloc.dart';
import 'package:task_nibbles/features/tasks/ui/widgets/task_tile.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTaskListBloc extends MockBloc<TaskListEvent, TaskListState>
    implements TaskListBloc {}

class MockConnectivityCubit extends MockCubit<ConnectivityStatus>
    implements ConnectivityCubit {}

class MockGamificationCubit extends MockCubit<GamificationState>
    implements GamificationCubit {}

// ── Test data ─────────────────────────────────────────────────────────────────

Task _makeTask({
  String id = 'task-1',
  bool isOverdue = false,
  TaskStatus status = TaskStatus.pending,
}) =>
    Task(
      id: id,
      title: 'Test Task',
      priority: TaskPriority.high,
      taskType: TaskType.oneTime,
      status: status,
      isOverdue: isOverdue,
      sortOrder: 0,
      isDetached: false,
      attachmentCount: 0,
      createdAt: DateTime(2026, 5, 15),
      updatedAt: DateTime(2026, 5, 15),
      endAt: isOverdue ? DateTime(2026, 5, 10) : null,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockTaskListBloc mockBloc;

  setUpAll(() {
    registerFallbackValue(const CompleteTask(''));
  });

  setUp(() {
    mockBloc = MockTaskListBloc();
    when(() => mockBloc.state).thenReturn(
      const TaskListLoaded(
        tasks: [],
        activeFilter: TaskFilter.empty,
        isOffline: false,
      ),
    );
  });

  Widget buildSubject(Task task) => MaterialApp(
        home: Scaffold(
          body: BlocProvider<TaskListBloc>.value(
            value: mockBloc,
            child: TaskTile(task: task),
          ),
        ),
      );

  group('TaskTile widget tests', () {
    testWidgets('overdue chip is visible when is_overdue=true', (tester) async {
      await tester.pumpWidget(buildSubject(_makeTask(isOverdue: true)));

      // The chip is keyed — check it exists.
      expect(
        find.byKey(const Key('task_tile_overdue_chip')),
        findsOneWidget,
      );
    });

    testWidgets('overdue chip is NOT visible for non-overdue task',
        (tester) async {
      await tester.pumpWidget(buildSubject(_makeTask(isOverdue: false)));

      expect(
        find.byKey(const Key('task_tile_overdue_chip')),
        findsNothing,
      );
    });

    testWidgets('complete button dispatches CompleteTask event', (tester) async {
      final task = _makeTask();
      await tester.pumpWidget(buildSubject(task));

      await tester.tap(find.byKey(Key('task_tile_complete_${task.id}')));
      await tester.pump();

      verify(() => mockBloc.add(CompleteTask(task.id))).called(1);
    });

    testWidgets('complete button is absent for completed tasks', (tester) async {
      final task = _makeTask(status: TaskStatus.completed);
      await tester.pumpWidget(buildSubject(task));

      expect(
        find.byKey(Key('task_tile_complete_${task.id}')),
        findsNothing,
      );
    });
  });
}
