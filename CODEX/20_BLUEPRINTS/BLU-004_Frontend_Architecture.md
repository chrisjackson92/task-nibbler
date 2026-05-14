---
id: BLU-004
title: "Mobile Architecture Blueprint — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [architecture, flutter, mobile, dart]
related: [BLU-003, CON-001, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Complete Flutter mobile architecture for Task Nibbles. Covers project structure, BLoC state management, Dio API client, Hive offline cache, Rive animations, navigation, theming, and testing strategy. The Mobile Developer Agent builds against this document.

# Mobile Architecture Blueprint — Task Nibbles

---

## 1. Technology Stack

| Component | Package | Version |
|:----------|:--------|:--------|
| Language | Dart | 3.3+ |
| Framework | Flutter | 3.22+ |
| Version manager | FVM (Flutter Version Manager) | 3.x |
| State management | flutter_bloc | ^8.1 |
| HTTP client | dio | ^5.4 |
| Token storage | flutter_secure_storage | ^9.0 |
| Local cache | hive + hive_flutter | ^2.2 |
| Animations | rive | ^0.13 |
| Navigation | go_router | ^14.0 |
| Image/video picker | image_picker | ^1.1 |
| Video playback | video_player | ^2.8 |
| Offline detection | connectivity_plus | ^6.0 |
| API code generation | openapi-generator (dart-dio template) | — |
| UI components | Material 3 (built-in) | — |
| Testing | flutter_test + bloc_test + mocktail | — |

---

## 2. Project Structure

```
mobile/
├── lib/
│   ├── main.dart                    # App entry point — initialises Hive, BLoC, router
│   │
│   ├── core/                        # Shared infrastructure — used across all features
│   │   ├── api/
│   │   │   ├── api_client.dart      # Dio instance with base URL + interceptors
│   │   │   └── interceptors/
│   │   │       ├── auth_interceptor.dart    # Injects Bearer token; handles 401 → silent refresh
│   │   │       └── logging_interceptor.dart # Request/response structured logging (debug only)
│   │   │
│   │   ├── auth/
│   │   │   └── token_storage.dart   # flutter_secure_storage wrapper for access + refresh tokens
│   │   │
│   │   ├── cache/
│   │   │   └── task_cache.dart      # Hive box wrapper — read/write task list for offline use
│   │   │
│   │   ├── connectivity/
│   │   │   └── connectivity_cubit.dart  # Emits ConnectedState / DisconnectedState
│   │   │
│   │   ├── router/
│   │   │   └── app_router.dart      # go_router config — all named routes + auth guard
│   │   │
│   │   ├── theme/
│   │   │   ├── app_theme.dart       # MaterialTheme — light + dark; color scheme, typography
│   │   │   └── app_colors.dart      # Color constants
│   │   │
│   │   ├── widgets/
│   │   │   ├── offline_banner.dart  # Banner shown when ConnectedState = offline
│   │   │   ├── error_snackbar.dart  # Standardised error display
│   │   │   └── loading_overlay.dart # Full-screen loading indicator
│   │   │
│   │   └── di/
│   │       └── injection.dart       # Simple manual DI (GetIt or constructor injection)
│   │
│   └── features/                    # Feature-first layout — one folder per domain
│       │
│       ├── auth/
│       │   ├── data/
│       │   │   └── auth_repository.dart      # Wraps generated Dio auth API client
│       │   ├── bloc/
│       │   │   ├── auth_bloc.dart            # AuthBloc: events (Login, Register, Logout, Delete)
│       │   │   └── auth_state.dart           # AuthState: Initial, Loading, Authenticated, Unauthenticated, Error
│       │   └── ui/
│       │       ├── login_screen.dart
│       │       ├── register_screen.dart
│       │       ├── forgot_password_screen.dart
│       │       └── reset_password_screen.dart # Deep-linked from email
│       │
│       ├── tasks/
│       │   ├── data/
│       │   │   └── task_repository.dart      # Wraps task API client + Hive cache
│       │   ├── bloc/
│       │   │   ├── task_list_bloc.dart        # TaskListBloc: load, filter, sort, reorder
│       │   │   ├── task_list_state.dart
│       │   │   ├── task_detail_cubit.dart     # TaskDetailCubit: single task + complete/cancel
│       │   │   └── task_form_cubit.dart       # TaskFormCubit: create/edit form state
│       │   └── ui/
│       │       ├── task_list_screen.dart      # Home screen — includes gamification hero
│       │       ├── task_detail_screen.dart
│       │       ├── task_form_screen.dart      # Create and edit (same form)
│       │       ├── widgets/
│       │       │   ├── task_tile.dart         # List item — priority chip, status, overdue indicator
│       │       │   ├── task_filter_sheet.dart # Bottom sheet: filter/sort controls
│       │       │   └── overdue_chip.dart      # Red date chip for overdue tasks
│       │       └── gamification/
│       │           └── hero_section.dart      # Collapsible hero: sprite + tree bar + streak
│       │
│       ├── attachments/
│       │   ├── data/
│       │   │   └── attachment_repository.dart # Wraps attachment API + S3 direct upload
│       │   ├── bloc/
│       │   │   └── attachment_cubit.dart      # Handles upload flow: pick → pre-register → upload to S3 → confirm
│       │   └── ui/
│       │       ├── attachment_list_widget.dart
│       │       ├── attachment_viewer_screen.dart # Full-screen image
│       │       └── video_player_screen.dart
│       │
│       ├── gamification/
│       │   ├── data/
│       │   │   └── gamification_repository.dart
│       │   ├── bloc/
│       │   │   └── gamification_cubit.dart    # Fetches state + badges; drives Rive animations
│       │   └── ui/
│       │       ├── gamification_detail_screen.dart # Full tree Rive + badge shelf
│       │       ├── widgets/
│       │       │   ├── sprite_widget.dart     # Rive sprite companion animation
│       │       │   ├── tree_widget.dart       # Rive tree animation
│       │       │   ├── badge_shelf_widget.dart
│       │       │   └── streak_counter_widget.dart
│       │       └── badge_award_overlay.dart   # Celebration animation on badge unlock
│       │
│       └── settings/
│           ├── bloc/
│           │   └── settings_cubit.dart        # Logout, delete account flows
│           └── ui/
│               └── settings_screen.dart       # Logout, delete account, change password
│
├── assets/
│   ├── animations/
│   │   ├── sprite.riv               # Sprite companion Rive file (4 states)
│   │   └── tree.riv                 # Tree Rive file (4 states)
│   └── fonts/                       # Custom fonts if used (configured in pubspec.yaml)
│
├── test/
│   ├── features/
│   │   ├── auth/bloc/auth_bloc_test.dart
│   │   ├── tasks/bloc/task_list_bloc_test.dart
│   │   └── ...
│   └── core/
│       └── api/interceptors/auth_interceptor_test.dart
│
├── integration_test/
│   └── app_test.dart               # End-to-end: login → create task → complete → check gamification
│
└── pubspec.yaml
```

---

## 3. BLoC Pattern (State Management)

Task Nibbles uses **BLoC** for complex multi-event flows (auth, task list) and **Cubit** for simpler single-state domains (task detail, form, gamification, settings).

### BLoC vs. Cubit Decision Matrix

| Feature | Type | Rationale |
|:--------|:-----|:----------|
| Auth | BLoC | Multiple events (Login, Register, Logout, Delete, TokenRefresh) |
| Task List | BLoC | Multiple events (Load, Filter, Sort, Reorder, Complete, Cancel) |
| Task Detail | Cubit | Single-purpose: display task + trigger actions |
| Task Form | Cubit | Form state is simple validated input |
| Attachments | Cubit | Upload pipeline: linear state progression |
| Gamification | Cubit | Fetch state once, update on completion |
| Connectivity | Cubit | Simple boolean-like: online/offline |
| Settings | Cubit | Two actions: logout, delete account |

### State Pattern

```dart
// Example: TaskListState
sealed class TaskListState {}
class TaskListInitial extends TaskListState {}
class TaskListLoading extends TaskListState {}
class TaskListLoaded extends TaskListState {
  final List<Task> tasks;
  final TaskFilter activeFilter;
  final bool isOffline; // true = loaded from Hive cache
}
class TaskListError extends TaskListState {
  final String message;
}
```

---

## 4. API Client — Dio + OpenAPI Codegen

### Code Generation

```bash
# From the repo root — run whenever shared/openapi.yaml changes
openapi-generator generate \
  -i ../shared/openapi.yaml \
  -g dart-dio \
  -o mobile/lib/core/api/generated \
  --additional-properties=pubName=task_nibbles_api,nullableFields=true
```

The generated client is **checked into git** — it's regenerated only when the API contract changes (new PR required to review generated changes).

### Dio Instance

```dart
// core/api/api_client.dart
Dio createDioClient(String baseUrl, TokenStorage tokenStorage) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.addAll([
    AuthInterceptor(dio, tokenStorage),  // JWT inject + silent refresh
    if (kDebugMode) LoggingInterceptor(),
  ]);

  return dio;
}
```

### Silent Refresh Interceptor

```dart
// core/api/interceptors/auth_interceptor.dart
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(options, handler) async {
    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  void onError(error, handler) async {
    if (error.response?.statusCode == 401) {
      // Attempt silent refresh
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        // Retry original request with new token
        return handler.resolve(await _dio.fetch(error.requestOptions));
      }
      // Refresh failed — emit auth failure, redirect to login
      _authBloc.add(AuthTokenExpired());
    }
    return handler.next(error);
  }
}
```

---

## 5. Hive Offline Cache

```dart
// core/cache/task_cache.dart
class TaskCache {
  static const String _boxName = 'tasks';

  Future<void> saveTasks(List<Task> tasks) async {
    final box = await Hive.openBox<Map>(_boxName);
    await box.clear();
    for (final task in tasks) {
      await box.put(task.id, task.toJson());
    }
  }

  Future<List<Task>> loadTasks() async {
    final box = await Hive.openBox<Map>(_boxName);
    return box.values
        .map((json) => Task.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }
}
```

**Cache policy:**
- Cache is written every time `GET /tasks` returns successfully
- Cache is read when `ConnectivityCubit` emits `DisconnectedState`
- Cache is invalidated (cleared) on logout or account deletion

---

## 6. Navigation — go_router

```dart
// core/router/app_router.dart
final router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final isAuth = context.read<AuthBloc>().state is AuthAuthenticated;
    final isOnAuthPage = state.matchedLocation.startsWith('/login')
                      || state.matchedLocation.startsWith('/register');
    if (!isAuth && !isOnAuthPage) return '/login';
    if (isAuth && isOnAuthPage) return '/tasks';
    return null;
  },
  routes: [
    GoRoute(path: '/login',          builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register',       builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/forgot-password',builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/reset-password', builder: (_, state) =>
        ResetPasswordScreen(token: state.uri.queryParameters['token']!)),

    GoRoute(path: '/tasks',          builder: (_, __) => const TaskListScreen()),
    GoRoute(path: '/tasks/new',      builder: (_, __) => const TaskFormScreen()),
    GoRoute(path: '/tasks/:id',      builder: (_, state) =>
        TaskDetailScreen(taskId: state.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/edit', builder: (_, state) =>
        TaskFormScreen(taskId: state.pathParameters['id'])),

    GoRoute(path: '/gamification',   builder: (_, __) => const GamificationDetailScreen()),
    GoRoute(path: '/settings',       builder: (_, __) => const SettingsScreen()),
  ],
);
```

**Deep linking:**
- Password reset email links to `tasknibbles://reset-password?token=<raw>` (Flutter universal link)
- Configured in `AndroidManifest.xml` and `Info.plist`

---

## 7. Rive Animations

### Asset Files
- `assets/animations/sprite.riv` — Sprite companion
- `assets/animations/tree.riv` — Tree

Both files must define named **State Machines** and **inputs** for the Flutter widget to drive programmatically.

### Sprite Rive Spec

```
State Machine: "SpriteSM"
States: Welcome → Happy → Neutral → Sad
Input: "state" (String trigger)
  - "welcome"  → plays welcome animation loop
  - "happy"    → plays cheering/jumping loop
  - "neutral"  → plays idle animation loop
  - "sad"      → plays drooping/wilting loop
```

### Tree Rive Spec

```
State Machine: "TreeSM"
States: Thriving → Healthy → Struggling → Withering
Input: "health" (Number 0–100)
  - Transitions driven by numeric threshold triggers
```

### Widget Usage

```dart
// features/gamification/ui/widgets/sprite_widget.dart
class SpriteWidget extends StatefulWidget {
  final GamificationState state;
}

class _SpriteWidgetState extends State<SpriteWidget> {
  late RiveAnimationController _controller;
  SMITrigger? _stateTrigger;

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/animations/sprite.riv',
      stateMachines: ['SpriteSM'],
      onInit: (artboard) {
        final controller = StateMachineController.fromArtboard(artboard, 'SpriteSM')!;
        artboard.addController(controller);
        _stateTrigger = controller.findInput<bool>('happy') as SMITrigger;
        _updateState(widget.state);
      },
    );
  }
}
```

> [!IMPORTANT]
> Rive `.riv` files must be created BEFORE Sprint 4 begins. This is a **blocking dependency** on SPR-004-MB. See PRJ-001 §9 Open Decision #2.

---

## 8. Home Screen — Gamification Hero Section

```
┌─────────────────────────────────────┐
│  ┌──────────┐  🌿 Tree Health: 72%  │
│  │  [SPRITE] │  ████████░░           │  ← Hero section (collapsible)
│  │  HAPPY   │  🔥 Streak: 7 days    │
│  └──────────┘                        │
├─────────────────────────────────────┤
│  [+ New Task]  [Filter ▼]  [Sort ▼] │
├─────────────────────────────────────┤
│  ○ High  Buy groceries         3pm  │
│  ○ Med   Call dentist               │  ← Task list
│  ● Low   Read 10 pages    ✓ Done    │
│  🔴 Crit Email team report  OVERDUE │
└─────────────────────────────────────┘
```

**Hero section behaviour:**
- Collapsed by default when task list is long (user scrolls, hero collapses)
- Expanded on app open / when list is at top
- Tapping hero → navigates to `/gamification` detail screen
- Sprite and tree health bar use placeholder visuals (solid colour block) in Sprints 1–3; replaced by Rive in Sprint 4

---

## 9. Offline Behaviour

```dart
// core/connectivity/connectivity_cubit.dart
class ConnectivityCubit extends Cubit<ConnectivityStatus> {
  ConnectivityCubit() : super(ConnectivityStatus.connected) {
    Connectivity().onConnectivityChanged.listen((result) {
      emit(result == ConnectivityResult.none
          ? ConnectivityStatus.disconnected
          : ConnectivityStatus.connected);
    });
  }
}
```

**Write actions disabled when offline:**
- FAB (+ New Task) shows `offline_banner.dart` tooltip instead of navigating
- Complete/Cancel task buttons are disabled with greyed styling
- Attachment picker is disabled
- All BLoC `AddTask`, `CompleteTask`, `CancelTask` events guard against `isOffline`

---

## 10. Theme

```dart
// core/theme/app_theme.dart
// Material 3, seed-colour based
final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4CAF50), // Leafy green — ties to tree motif
    brightness: Brightness.light,
  ),
  textTheme: GoogleFonts.outfitTextTheme(), // or Inter
);

final darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4CAF50),
    brightness: Brightness.dark,
  ),
  textTheme: GoogleFonts.outfitTextTheme(),
);
```

---

## 11. Testing Strategy (GOV-002 Compliant)

| Layer | Approach | Tool |
|:------|:---------|:-----|
| BLoC/Cubit | Unit tests for every state transition | `bloc_test` |
| Repositories | Unit tests with mock Dio (MockAdapter) | `mocktail` |
| Widgets | Widget tests for key screens (login, task list, hero) | `flutter_test` |
| Integration | End-to-end: login → create task → complete → hero updates | `integration_test` |
| Auth interceptor | Unit test silent refresh flow (401 → refresh → retry) | `mocktail` |
| Coverage target | ≥ 70% (enforced in CI) | `flutter test --coverage` |

---

> *Read next: CON-001 (Transport Contract), CON-002 (API Contract)*
