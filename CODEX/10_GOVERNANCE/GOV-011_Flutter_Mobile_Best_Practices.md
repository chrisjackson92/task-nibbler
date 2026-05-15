---
id: GOV-011
title: "Flutter Mobile Best Practices — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [coding, standards, governance, flutter, dart, bloc, dio, hive, mobile]
related: [GOV-003, GOV-004, BLU-004, AGT-002-MB]
created: 2026-05-15
updated: 2026-05-15
version: 1.0.0
---

> **BLUF:** Non-obvious, stack-specific best practices for the Flutter + BLoC + Dio + Hive + Rive mobile app. Read alongside GOV-003 (general coding standard). Items here are either Dart-idiomatic requirements or common failure modes in Flutter agentic codebases.

# Flutter Mobile Best Practices

---

## 1. BLoC vs Cubit Decision Matrix

The project uses both BLoC and Cubit. Use the right tool for the job (see also BLU-004 §3).

| Scenario | Use |
|:---------|:----|
| Simple toggle, counter, loading flag | **Cubit** |
| Complex multi-step user flow with event types | **BLoC** |
| Auth state machine (login → authenticated → expired) | **BLoC** |
| Gamification state (just fetch + display) | **Cubit** |
| Task list with filter/sort/refresh events | **BLoC** |

### 1.1 State Classes Must Be Immutable
```dart
// ✅ Correct — extend Equatable, all fields final
class TaskLoaded extends TaskState {
  const TaskLoaded({required this.tasks});
  final List<Task> tasks;

  @override
  List<Object?> get props => [tasks];
}

// ❌ Wrong — mutable state causes missed rebuilds
class TaskLoaded extends TaskState {
  List<Task> tasks = [];  // no Equatable, no const
}
```

### 1.2 Use `copyWith` for State Updates
Never mutate a state object. Emit a new one:
```dart
emit(state.copyWith(isLoading: true));
```

---

## 2. Widget Patterns

### 2.1 `const` Constructors Everywhere Possible
Every widget that doesn't depend on runtime data should be `const`. This is a performance requirement, not a style preference — `const` widgets are never rebuilt.
```dart
// ✅
const SizedBox(height: 16),
const Divider(),
Text(task.title),   // ← can't be const (runtime data)
```

### 2.2 `BlocBuilder` with `buildWhen` to Prevent Over-Rebuilding
Without `buildWhen`, the entire subtree rebuilds on every state change:
```dart
BlocBuilder<TaskBloc, TaskState>(
  buildWhen: (prev, curr) => prev.tasks != curr.tasks,
  builder: (context, state) => TaskListView(tasks: state.tasks),
)
```

### 2.3 Prefer `BlocSelector` for Reading a Single Field
```dart
BlocSelector<TaskBloc, TaskState, bool>(
  selector: (state) => state.isLoading,
  builder: (context, isLoading) =>
      isLoading ? const CircularProgressIndicator() : const SizedBox.shrink(),
)
```

### 2.4 Do Not Read BLoC/Cubit State with `context.read()` in `build()`
`context.read()` does not rebuild on state change. Use it only in callbacks:
```dart
// ✅ In a button callback
onPressed: () => context.read<TaskBloc>().add(CompleteTask(id: task.id)),

// ❌ In build() — won't update UI
final tasks = context.read<TaskBloc>().state.tasks;
```

### 2.5 Avoid the `Opacity` Widget for Animations
`Opacity` causes full repaint on every frame. Use `AnimatedOpacity` or `FadeTransition` (uses a layer, not repaint):
```dart
// ❌ Avoid for animated opacity
Opacity(opacity: _controller.value, child: widget)

// ✅ Use a transition
FadeTransition(opacity: _controller, child: widget)
```

---

## 3. Navigation (go_router)

### 3.1 All Routes Defined in a Single Router File
Routes live in `lib/core/router/app_router.dart`. Never instantiate `GoRouter` in individual screens.

### 3.2 Use Typed Routes
```dart
// ✅ Type-safe navigation — compile error if params are wrong
const TaskDetailRoute(taskId: task.id).go(context);

// ❌ String-based — silently fails at runtime
context.go('/tasks/${task.id}');
```

### 3.3 Redirect Guard for Auth
The router must check auth state and redirect unauthenticated users to `/login`:
```dart
redirect: (context, state) {
  final isLoggedIn = context.read<AuthBloc>().state is Authenticated;
  if (!isLoggedIn && !state.matchedLocation.startsWith('/auth')) {
    return '/auth/login';
  }
  return null;
},
```

---

## 4. Dio & API Client

### 4.1 All API Errors Must Go Through the Dio Interceptor
Never write `try/catch` around individual `dio.get()` calls in the repository. The error interceptor normalises all API failures into typed `ApiException` objects.

### 4.2 Silent Refresh: Block Concurrent Calls During Token Refresh
A common bug is sending multiple refresh requests when several calls 401 simultaneously. Use a lock:
```dart
// In DioAuthInterceptor
if (_isRefreshing) {
  // Queue the request and retry after refresh completes
  return _retryQueue.add(options);
}
_isRefreshing = true;
// ... refresh token ...
_isRefreshing = false;
```

### 4.3 Never Log Raw Tokens
The Dio logger interceptor must mask the `Authorization` header:
```dart
// In LogInterceptor options:
requestHeader: false,  // or sanitise manually
```

### 4.4 Retry After Refresh — Don't Lose the Original Request
After a successful token refresh, the interceptor must replay the original request with the new token, not just continue. Use `handler.resolve(response)` with the retried call.

---

## 5. Hive Offline Cache

### 5.1 One Box Per Domain Entity
```
tasks_box       → List<TaskHiveModel>
auth_box        → AuthTokens (access + refresh)
gamification_box → GamificationStateHiveModel
```
Never store everything in a single `app_box`.

### 5.2 Always Register Type Adapters Before `openBox`
In `main.dart`, before `runApp`:
```dart
Hive.registerAdapter(TaskHiveModelAdapter());
Hive.registerAdapter(GamificationStateHiveModelAdapter());
await Hive.openBox<TaskHiveModel>('tasks_box');
```
Missing adapter registration causes a silent runtime crash.

### 5.3 Use `flutter_secure_storage` for Tokens, Not Hive
Auth tokens (access + refresh JWTs) must use `flutter_secure_storage` — it uses iOS Keychain and Android Keystore. Hive is unencrypted on disk. Hive is for non-secret cache data only.

### 5.4 Invalidate Cache on Logout
On logout or account deletion, clear all Hive boxes:
```dart
await Hive.box<TaskHiveModel>('tasks_box').clear();
```

---

## 6. Rive Animations

### 6.1 Wrap Rive Widget in `RepaintBoundary`
Rive renders every frame. Without `RepaintBoundary`, it invalidates parent widget paint:
```dart
RepaintBoundary(
  child: RiveAnimation.asset('assets/sprite.riv', ...),
)
```

### 6.2 State Machine Input Names Must Match the `.riv` Asset Exactly
State machine inputs are stringly typed at runtime. A typo causes a silent no-op:
```dart
// In the .riv file the input is named "mood" (lowercase)
final moodInput = controller.findInput<double>('mood');
// 'Mood' ❌ — null, animation won't run
// 'mood' ✅
```

### 6.3 Dispose `RiveAnimationController` in Widget Dispose
```dart
@override
void dispose() {
  _riveController.dispose();
  super.dispose();
}
```

---

## 7. Dart Language Patterns

### 7.1 Use Sealed Classes for State Hierarchies (Dart 3+)
```dart
sealed class TaskState {}
final class TaskInitial extends TaskState {}
final class TaskLoading extends TaskState {}
final class TaskLoaded extends TaskState { final List<Task> tasks; ... }
final class TaskError   extends TaskState { final String message; ... }
```
Sealed classes make exhaustive `switch` expressions compile-time safe — no missed state.

### 7.2 Use `freezed` for Complex Data Models
For domain models with `copyWith`, `==`, `hashCode`, and JSON serialisation, use `freezed` + `json_serializable`. Do not hand-write these for non-trivial classes.

### 7.3 Prefer `final` Everywhere
All local variables and fields that are not reassigned must be `final`. The linter (`prefer_final_locals`) enforces this.

### 7.4 Avoid `dynamic` — Use Generics or Typed Unions
```dart
// ❌
dynamic result = await api.fetchTask(id);

// ✅
final Task result = await taskRepository.getTask(id);
```

### 7.5 `async`/`await` Over `.then()` Chains
`.then()` chains are harder to read and lose stack traces on errors. Use `async`/`await` throughout.

---

## 8. Testing

### 8.1 Widget Tests: Use `pumpAndSettle` After Async Operations
```dart
await tester.tap(find.byKey(const Key('complete_button')));
await tester.pumpAndSettle();  // waits for all animations and async gaps
```

### 8.2 BLoC Tests: Use `bloc_test` Package's `blocTest`
```dart
blocTest<TaskBloc, TaskState>(
  'emits TaskLoaded when LoadTasks succeeds',
  build: () => TaskBloc(repository: mockRepo),
  act: (bloc) => bloc.add(const LoadTasks()),
  expect: () => [isA<TaskLoading>(), isA<TaskLoaded>()],
);
```

### 8.3 Mock Repositories with `mocktail` (Not `mockito`)
`mocktail` requires no code generation and works cleanly with nullable types:
```dart
class MockTaskRepository extends Mock implements TaskRepository {}
when(() => mockRepo.getTasks()).thenAnswer((_) async => []);
```

### 8.4 Golden Tests for Gamification UI Components
The Rive hero section and badge shelf are complex visual components. Maintain golden test files (`.png` snapshots) in `test/goldens/` and verify them in CI:
```dart
await expectLater(find.byType(BadgeShelf), matchesGoldenFile('goldens/badge_shelf.png'));
```

---

## 9. Performance & Platform

### 9.1 List Performance: Use `ListView.builder`, Never `ListView` with Children
```dart
// ❌ Builds all children upfront — bad for long task lists
ListView(children: tasks.map((t) => TaskCard(t)).toList())

// ✅ Builds only visible items
ListView.builder(
  itemCount: tasks.length,
  itemBuilder: (ctx, i) => TaskCard(tasks[i]),
)
```

### 9.2 Image Caching: Use `cached_network_image` for Attachment Thumbnails
Never load attachment images with plain `Image.network` — it re-downloads on every frame rebuild.

### 9.3 iOS: `NSPhotoLibraryUsageDescription` Required
`image_picker` requires this key in `Info.plist` for SPR-003-MB. Missing it causes a crash on iOS without a debug error message.

### 9.4 Android: Request `READ_MEDIA_IMAGES` for Android 13+
The old `READ_EXTERNAL_STORAGE` permission is rejected on Android 13+. Use `permission_handler` to request `Permission.photos`.

---

## 10. Project Conventions

| Convention | Rule |
|:-----------|:-----|
| File naming | `snake_case.dart` for all files |
| Class naming | `PascalCase` |
| Feature folders | Each feature owns its `bloc/`, `repository/`, `screens/`, `widgets/` subdirectories (feature-first layout) |
| `print()` | Forbidden — use `slog` equivalent (`developer.log` or structured logging package) |
| `BuildContext` across async gaps | Always check `mounted` before using context after `await` |
| Magic strings | No bare string route paths, no bare string Hive box names — use constants |

---

> *These practices are standing rules for all mobile sprints. Violations found at audit become DEF- reports.*
