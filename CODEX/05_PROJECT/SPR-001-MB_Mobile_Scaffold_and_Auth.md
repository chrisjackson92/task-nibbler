---
id: SPR-001-MB
title: "Sprint 1 — Mobile Scaffold & Auth"
type: sprint
status: MERGED
assignee: coder
agent_boot: AGT-002-MB_Mobile_Developer_Agent.md
sprint_number: 1
track: mobile
estimated_days: 5
blocked_by: "None — SPR-001-BE staging live at task-nibbles-api-staging.fly.dev ✅"
related: [BLU-004, CON-001, CON-002, PRJ-001, GOV-011]
created: 2026-05-14
updated: 2026-05-15
---

> **BLUF:** Bootstrap the entire Flutter project and implement all authentication screens and infrastructure. By the end of this sprint: the app runs on a physical device, can register/login/forgot-password, stores tokens securely, performs silent refresh on 401, shows an offline banner, and has a collapsible gamification hero placeholder on the home screen.

> [!NOTE]
> **Status: READY.** Staging API is live at `task-nibbles-api-staging.fly.dev`. Auth endpoints (register, login, refresh, forgot-password, reset-password) are all deployed and verified (AUD-001-BE ✅).

# Sprint 1-MB — Mobile Scaffold & Auth

---

## Pre-Conditions (Must be TRUE before starting)

- [x] `SPR-001-BE` complete — staging API live at `task-nibbles-api-staging.fly.dev` (AUD-001-BE APPROVED 2026-05-15)
- [x] `SPR-002-BE` task endpoints merged to develop (AUD-002-BE APPROVED 2026-05-15) — not required for this sprint but means staging deploy will include them
- [ ] Read `AGT-002-MB_Mobile_Developer_Agent.md` in full
- [ ] Read `GOV-011_Flutter_Mobile_Best_Practices.md` in full ← **NEW — mandatory reading**
- [ ] Read `BLU-004_Frontend_Architecture.md` in full
- [ ] Read `CON-001_Transport_Contract.md` in full
- [ ] Read `CON-002_API_Contract.md` §1 (Auth routes) in full
- [ ] Read `PRJ-001` §4 (User Flows) and §5.1 (Auth spec) in full
- [ ] FVM + Flutter 3.22+ installed and verified
- [ ] Branch `feature/M-001-mobile-scaffold` forked from `develop`
- [ ] Physical device or emulator available for testing

---

## Exit Criteria (Sprint is DONE when ALL pass)

- [ ] App launches on Android or iOS without crash
- [ ] Register screen creates account and navigates to task list
- [ ] Login screen authenticates and navigates to task list
- [ ] Forgot password screen submits email (Resend email received in test inbox)
- [ ] Reset password deep link (`tasknibbles://reset-password?token=...`) opens reset screen
- [ ] Settings screen accessible; logout clears tokens and returns to login
- [ ] Delete account flow: confirmation dialog → `DELETE /auth/account` → redirect to login
- [ ] Silent refresh: access token auto-renewed on 401 without user interaction
- [ ] Offline banner appears when device goes offline; disappears when reconnected
- [ ] Home screen loads (empty task list placeholder) with gamification hero section visible
- [ ] `fvm flutter test` passes with ≥ 70% BLoC coverage
- [ ] No tokens stored in `SharedPreferences` — only `flutter_secure_storage`

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| M-001 | Flutter project init (FVM, feature-first structure) | Use folder structure from BLU-004 §2 exactly |
| M-002 | Dio API client setup + base URL (staging/prod via dart-define) | See BLU-004 §4 |
| M-003 | OpenAPI codegen: Dart models + Dio client | Run `openapi-generator` against `shared/openapi.yaml` |
| M-004 | AuthBloc scaffold (events: Login, Register, Logout, DeleteAccount, TokenExpired) | See BLU-004 §3 for state pattern |
| M-005 | flutter_secure_storage: access + refresh token persistence | TokenStorage class in `core/auth/` |
| M-006 | AuthInterceptor: inject Bearer token + silent refresh on 401 | See BLU-004 §4 for interceptor code |
| M-007 | Login screen UI | Email + password fields; loading state; error snackbar |
| M-008 | Register screen UI | Email + password + timezone picker (optional in v1, defaults to 'UTC') |
| M-009 | Forgot password screen + reset deep link handling | See BLU-004 §7 for deep link config |
| M-010 | Settings screen (logout + delete account) | Delete requires confirmation dialog |
| M-011 | Hive init: open task box in main.dart | `await Hive.initFlutter(); Hive.openBox('tasks');` |
| M-012 | ConnectivityCubit + OfflineBanner widget | Banner shown at top of every screen when offline |
| M-013 | Home screen gamification hero section (placeholder) | Static colour block; Rive added in SPR-004-MB |

---

## Technical Notes

### Timezone Field on Register
The `timezone` field in `POST /auth/register` is optional (defaults to `UTC`). For Sprint 1, register with `timezone: 'UTC'` — a timezone picker can be added later. Do not block registration on this.

### Silent Refresh Interceptor Critical Behaviour
The `AuthInterceptor` must queue concurrent 401 requests rather than firing multiple refresh calls:

```dart
bool _isRefreshing = false;
final List<(RequestOptions, ErrorInterceptorHandler)> _queue = [];

@override
void onError(DioException err, ErrorInterceptorHandler handler) async {
  if (err.response?.statusCode == 401 && !_isRefreshing) {
    _isRefreshing = true;
    final refreshed = await _tryRefreshToken();
    _isRefreshing = false;
    if (refreshed) {
      // Retry all queued requests
      for (final (opts, h) in _queue) { ... }
      return handler.resolve(await _dio.fetch(err.requestOptions));
    }
    _authBloc.add(AuthTokenExpired());
  }
  handler.next(err);
}
```

### go_router Auth Guard
```dart
redirect: (context, state) {
  final isAuth = context.read<AuthBloc>().state is AuthAuthenticated;
  final isLoginPath = state.matchedLocation.startsWith('/login')
                   || state.matchedLocation.startsWith('/register')
                   || state.matchedLocation.startsWith('/forgot-password')
                   || state.matchedLocation.startsWith('/reset-password');
  if (!isAuth && !isLoginPath) return '/login';
  if (isAuth && isLoginPath) return '/tasks';
  return null;
},
```

### Gamification Hero (Sprint 1 Placeholder)
For Sprint 1, the hero section shows static placeholder content — no API call yet. The `GamificationCubit` is scaffolded but emits a hardcoded "WELCOME" state. The real gamification data fetch is implemented in SPR-004-MB.

```dart
// Sprint 1: placeholder
class GamificationCubit extends Cubit<GamificationState> {
  GamificationCubit() : super(const GamificationWelcome());
}
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `AuthBloc: login success → Authenticated state` | Unit (bloc_test) | ✅ |
| `AuthBloc: login failure → Error state with message` | Unit (bloc_test) | ✅ |
| `AuthBloc: TokenExpired event → Unauthenticated` | Unit (bloc_test) | ✅ |
| `AuthInterceptor: 401 → refresh → retry` | Unit (mocktail) | ✅ |
| `AuthInterceptor: refresh fails → AuthTokenExpired event` | Unit (mocktail) | ✅ |
| `ConnectivityCubit: offline → DisconnectedState` | Unit | ✅ |
| `LoginScreen widget: renders email + password fields` | Widget | ✅ |
| `SettingsScreen: logout button visible when authenticated` | Widget | ✅ |

---

## Architect Audit Checklist (Do not complete — Architect fills this)

- [ ] No token access outside `TokenStorage` and `AuthInterceptor`
- [ ] Deep link opens `/reset-password` screen on both Android and iOS
- [ ] Silent refresh confirmed via network intercept: single refresh call on concurrent 401s
- [ ] Offline banner visible when device network disabled
- [ ] Hero section renders without crash (placeholder state)
- [ ] `fvm flutter test` passes with no failures
- [ ] `flutter_secure_storage` confirmed as token store (not SharedPreferences)
