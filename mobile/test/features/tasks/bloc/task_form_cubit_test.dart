import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/task_models.dart';
import 'package:task_nibbles/features/tasks/bloc/task_form_cubit.dart';
import 'package:task_nibbles/features/tasks/data/task_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTaskRepository extends Mock implements TaskRepository {}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeCreateTaskRequest extends Fake implements CreateTaskRequest {}
class FakeUpdateTaskRequest extends Fake implements UpdateTaskRequest {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Task _makeTask([String id = 'task-1']) => Task(
      id: id,
      title: 'Test Task',
      priority: TaskPriority.medium,
      taskType: TaskType.oneTime,
      status: TaskStatus.pending,
      isOverdue: false,
      sortOrder: 0,
      isDetached: false,
      attachmentCount: 0,
      createdAt: DateTime(2026, 5, 15),
      updatedAt: DateTime(2026, 5, 15),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockTaskRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(FakeCreateTaskRequest());
    registerFallbackValue(FakeUpdateTaskRequest());
  });

  setUp(() {
    mockRepo = MockTaskRepository();
  });

  TaskFormCubit buildCubit() => TaskFormCubit(taskRepository: mockRepo);

  group('TaskFormCubit — submit (create)', () {
    blocTest<TaskFormCubit, TaskFormState>(
      'submit without title → TaskFormError',
      build: buildCubit,
      act: (cubit) => cubit.submit(
        const CreateTaskRequest(
          title: '',
          priority: TaskPriority.medium,
          taskType: TaskType.oneTime,
        ),
      ),
      expect: () => [
        isA<TaskFormError>().having(
          (e) => e.message,
          'message',
          contains('required'),
        ),
      ],
    );

    blocTest<TaskFormCubit, TaskFormState>(
      'submit with valid data → [Loading, Success]',
      build: buildCubit,
      setUp: () {
        when(() => mockRepo.createTask(any())).thenAnswer((_) async => _makeTask());
      },
      act: (cubit) => cubit.submit(
        const CreateTaskRequest(
          title: 'Buy groceries',
          priority: TaskPriority.high,
          taskType: TaskType.oneTime,
        ),
      ),
      expect: () => [
        isA<TaskFormLoading>(),
        isA<TaskFormSuccess>().having(
          (s) => s.task.id,
          'task.id',
          'task-1',
        ),
      ],
    );

    blocTest<TaskFormCubit, TaskFormState>(
      'submit with end before start → TaskFormError',
      build: buildCubit,
      act: (cubit) => cubit.submit(
        CreateTaskRequest(
          title: 'My Task',
          priority: TaskPriority.medium,
          taskType: TaskType.oneTime,
          startAt: DateTime(2026, 5, 15, 18),
          endAt: DateTime(2026, 5, 15, 17), // before start
        ),
      ),
      expect: () => [
        isA<TaskFormError>().having(
          (e) => e.message,
          'message',
          contains('End time'),
        ),
      ],
    );
  });
}
