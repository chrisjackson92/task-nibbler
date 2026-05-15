import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/task_models.dart';
import 'package:task_nibbles/core/cache/task_cache.dart';
import 'package:task_nibbles/core/connectivity/connectivity_cubit.dart';
import 'package:task_nibbles/features/gamification/bloc/gamification_cubit.dart';
import 'package:task_nibbles/features/tasks/bloc/task_list_bloc.dart';
import 'package:task_nibbles/features/tasks/data/task_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTaskRepository extends Mock implements TaskRepository {}
class MockTaskCache extends Mock implements TaskCache {}
class MockConnectivityCubit extends MockCubit<ConnectivityStatus>
    implements ConnectivityCubit {}
class MockGamificationCubit extends MockCubit<GamificationState>
    implements GamificationCubit {}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeUpdateTaskRequest extends Fake implements UpdateTaskRequest {}

// ── Test data ─────────────────────────────────────────────────────────────────

Task _makeTask({
  String id = 'task-1',
  String title = 'Test Task',
  TaskStatus status = TaskStatus.pending,
  TaskPriority priority = TaskPriority.medium,
  bool isOverdue = false,
  int sortOrder = 0,
}) =>
    Task(
      id: id,
      title: title,
      priority: priority,
      taskType: TaskType.oneTime,
      status: status,
      isOverdue: isOverdue,
      sortOrder: sortOrder,
      isDetached: false,
      attachmentCount: 0,
      createdAt: DateTime(2026, 5, 15),
      updatedAt: DateTime(2026, 5, 15),
    );

final _testTasks = [
  _makeTask(id: 'task-1', title: 'Buy groceries'),
  _makeTask(id: 'task-2', title: 'Call mum', isOverdue: true),
  _makeTask(id: 'task-3', title: 'Reading', status: TaskStatus.completed),
];

const _testDelta = GamificationDelta(
  streakCount: 3,
  treeHealthScore: 65,
  treeHealthDelta: 5,
  graceActive: false,
  badgesAwarded: [],
);

final _testCompleteResponse = CompleteTaskResponse(
  task: _testTasks[0].copyWith(status: TaskStatus.completed),
  gamificationDelta: _testDelta,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockTaskRepository mockRepo;
  late MockTaskCache mockCache;
  late MockConnectivityCubit mockConnectivity;
  late MockGamificationCubit mockGamification;

  setUpAll(() {
    registerFallbackValue(TaskFilter.empty);
    registerFallbackValue(FakeUpdateTaskRequest());
  });

  setUp(() {
    mockRepo = MockTaskRepository();
    mockCache = MockTaskCache();
    mockConnectivity = MockConnectivityCubit();
    mockGamification = MockGamificationCubit();

    // Default: online
    when(() => mockConnectivity.state).thenReturn(ConnectivityStatus.connected);
    // Default gamification state
    when(() => mockGamification.state).thenReturn(const GamificationWelcome());
    // Default: saveTasks no-op
    when(() => mockCache.saveTasks(any())).thenAnswer((_) async {});
  });

  TaskListBloc buildBloc() => TaskListBloc(
        taskRepository: mockRepo,
        taskCache: mockCache,
        connectivityCubit: mockConnectivity,
        gamificationCubit: mockGamification,
      );

  // ── Load ────────────────────────────────────────────────────────────────────

  group('TaskListBloc — LoadTasks', () {
    blocTest<TaskListBloc, TaskListState>(
      'emits [Loading, Loaded] when online load succeeds',
      build: buildBloc,
      setUp: () {
        when(() => mockRepo.getTasks(any())).thenAnswer(
          (_) async => TaskListResponse(
            data: _testTasks,
            meta: const PaginationMeta(
              total: 3,
              page: 1,
              perPage: 50,
              totalPages: 1,
            ),
          ),
        );
      },
      act: (bloc) => bloc.add(const LoadTasks()),
      expect: () => [
        isA<TaskListLoading>(),
        isA<TaskListLoaded>()
            .having((s) => s.tasks, 'tasks', _testTasks)
            .having((s) => s.isOffline, 'isOffline', isFalse),
      ],
    );

    // ── Offline ────────────────────────────────────────────────────────────────

    blocTest<TaskListBloc, TaskListState>(
      'emits Loaded(isOffline: true) when device is offline',
      build: buildBloc,
      setUp: () {
        when(() => mockConnectivity.state)
            .thenReturn(ConnectivityStatus.disconnected);
        when(() => mockCache.loadTasks()).thenAnswer((_) async => _testTasks);
      },
      act: (bloc) => bloc.add(const LoadTasks()),
      expect: () => [
        isA<TaskListLoading>(),
        isA<TaskListLoaded>()
            .having((s) => s.isOffline, 'isOffline', isTrue)
            .having((s) => s.tasks.length, 'tasks.length', 3),
      ],
    );
  });

  // ── Filter ─────────────────────────────────────────────────────────────────

  group('TaskListBloc — FilterTasks', () {
    blocTest<TaskListBloc, TaskListState>(
      'filter by OVERDUE returns only overdue tasks (offline path)',
      build: buildBloc,
      setUp: () {
        when(() => mockConnectivity.state)
            .thenReturn(ConnectivityStatus.disconnected);
        when(() => mockCache.loadTasks()).thenAnswer((_) async => _testTasks);
      },
      act: (bloc) => bloc.add(
        const FilterTasks(
          TaskFilter(status: FilterStatus.overdue),
        ),
      ),
      expect: () => [
        isA<TaskListLoading>(),
        isA<TaskListLoaded>().having(
          (s) => s.tasks,
          'tasks',
          predicate<List<Task>>(
            (tasks) => tasks.length == 1 && tasks[0].id == 'task-2',
          ),
        ),
      ],
    );
  });

  // ── Complete ───────────────────────────────────────────────────────────────

  group('TaskListBloc — CompleteTask', () {
    blocTest<TaskListBloc, TaskListState>(
      'complete task applies gamification delta and updates task in list',
      build: buildBloc,
      seed: () => TaskListLoaded(
        tasks: _testTasks,
        activeFilter: TaskFilter.empty,
        isOffline: false,
      ),
      setUp: () {
        when(() => mockRepo.completeTask('task-1'))
            .thenAnswer((_) async => _testCompleteResponse);
        // gamificationCubit.applyDelta — concrete call (not mocked return)
      },
      act: (bloc) => bloc.add(const CompleteTask('task-1')),
      expect: () => [
        isA<TaskListLoaded>().having(
          (s) => s.tasks.firstWhere((t) => t.id == 'task-1').status,
          'task-1 status',
          TaskStatus.completed,
        ),
      ],
      verify: (_) {
        verify(() => mockGamification.applyDelta(_testDelta)).called(1);
      },
    );
  });
}
