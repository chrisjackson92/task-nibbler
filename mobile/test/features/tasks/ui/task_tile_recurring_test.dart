import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/task_models.dart';
import 'package:task_nibbles/features/tasks/bloc/task_list_bloc.dart';
import 'package:task_nibbles/features/tasks/ui/widgets/task_tile.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTaskListBloc extends MockBloc<TaskListEvent, TaskListState>
    implements TaskListBloc {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Task _makeTask({String? recurringRuleId, bool isDetached = false}) => Task(
      id: 'task-1',
      title: 'My recurring task',
      priority: TaskPriority.medium,
      taskType: recurringRuleId != null ? TaskType.recurring : TaskType.oneTime,
      status: TaskStatus.pending,
      isOverdue: false,
      sortOrder: 0,
      isDetached: isDetached,
      attachmentCount: 0,
      recurringRuleId: recurringRuleId,
      createdAt: DateTime(2026, 5, 15),
      updatedAt: DateTime(2026, 5, 15),
    );

Widget buildTile(Task task, TaskListBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<TaskListBloc>.value(
        value: bloc,
        child: TaskTile(task: task),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockTaskListBloc mockBloc;

  setUp(() {
    mockBloc = MockTaskListBloc();
    when(() => mockBloc.state).thenReturn(
      const TaskListLoaded(
        tasks: [],
        activeFilter: TaskFilter(),
        isOffline: false,
      ),
    );
  });

  // ── M-039: recurring chip shown ──────────────────────────────────────────────

  testWidgets(
    'recurring task shows 🔁 chip when recurring_rule_id != null and not detached',
    (tester) async {
      final task = _makeTask(recurringRuleId: 'rule-1');
      await tester.pumpWidget(buildTile(task, mockBloc));
      await tester.pump();

      expect(find.byKey(const Key('task_tile_recurring_chip')), findsOneWidget);
    },
  );

  // ── M-039: no chip for ONE_TIME tasks ────────────────────────────────────────

  testWidgets(
    'one-time task does NOT show recurring chip',
    (tester) async {
      final task = _makeTask(); // recurringRuleId = null
      await tester.pumpWidget(buildTile(task, mockBloc));
      await tester.pump();

      expect(
          find.byKey(const Key('task_tile_recurring_chip')), findsNothing);
    },
  );

  // ── M-039: no chip when task is detached ─────────────────────────────────────

  testWidgets(
    'detached recurring task does NOT show recurring chip',
    (tester) async {
      final task = _makeTask(recurringRuleId: 'rule-1', isDetached: true);
      await tester.pumpWidget(buildTile(task, mockBloc));
      await tester.pump();

      expect(
          find.byKey(const Key('task_tile_recurring_chip')), findsNothing);
    },
  );
}
