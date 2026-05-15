---
id: AUD-005-MB
title: "Architect Audit — SPR-001-MB Mobile Scaffold & Auth"
type: audit
status: APPROVED_WITH_NOTES
sprint: SPR-001-MB
pr_branch: feature/M-001-mobile-scaffold
commit: a5ce3a8
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-001-MB **PASSES** audit. Flutter project is correctly structured (feature-first), AuthBloc covers all 7 events, TokenStorage exclusively uses `flutter_secure_storage`, the silent refresh interceptor correctly queues concurrent 401s, and go_router's auth guard is properly implemented. Three minor findings — none blocking. One required test (interceptor success-path retry) is missing and should be added before SPR-002-MB is started. **APPROVED to merge to `develop`.**

# Architect Audit — SPR-001-MB

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-001-MB — Mobile Scaffold & Auth |
| PR Branch | `feature/M-001-mobile-scaffold` |
| Commit | `a5ce3a8` |
| Files changed | 101 files, 5,579 insertions |
| Dart source files | 39 |
| Test files | 5 |
| Contracts audited against | CON-001, CON-002 §1, BLU-004, GOV-011, SPR-001-MB |

---

## BCK Tasks Delivered

| BCK ID | Status | Notes |
|:-------|:-------|:------|
| M-001 | ✅ PASS | Flutter project init — correct `feature/` directory structure |
| M-002 | ✅ PASS | Dio API client + `API_BASE_URL` dart-define (staging/prod switchable) |
| M-003 | ⚠️ NOTE | No OpenAPI codegen run — DTOs hand-written; acceptable for Sprint 1 if models match CON-002 |
| M-004 | ✅ PASS | AuthBloc with all 5 required events + ForgotPassword + ResetPassword |
| M-005 | ✅ PASS | `TokenStorage` wraps `flutter_secure_storage` exclusively |
| M-006 | ✅ PASS | `AuthInterceptor` — Bearer injection, silent refresh, concurrent 401 queue |
| M-007 | ✅ PASS | Login screen UI — email + password fields, loading state, error snackbar |
| M-008 | ✅ PASS | Register screen — email + password; timezone defaults to UTC per sprint spec |
| M-009 | ✅ PASS | Forgot password screen + deep link route `/reset-password?token=` |
| M-010 | ✅ PASS | Settings screen — logout + delete account with confirmation dialog |
| M-011 | ✅ PASS | Hive init in `main()`: `Hive.initFlutter()` + `Hive.openBox(kTaskBoxName)` |
| M-012 | ✅ PASS | `ConnectivityCubit` + `OfflineBanner` widget with 300ms animated slide |
| M-013 | ✅ PASS | Gamification hero placeholder — `GamificationWelcome()` state, gradient card, Rive deferred |

---

## Exit Criteria Verification

| Criterion | Result | Notes |
|:----------|:-------|:------|
| App structure follows BLU-004 §2 feature-first pattern | ✅ PASS | `lib/features/`, `lib/core/` correctly separated |
| `flutter_secure_storage` used for tokens — no `SharedPreferences` | ✅ PASS | No `SharedPreferences` import in production code anywhere |
| AuthBloc: Login → Authenticated | ✅ PASS | Tested |
| AuthBloc: Register → Authenticated | ✅ PASS | Tested |
| AuthBloc: TokenExpired → Unauthenticated + cache cleared | ✅ PASS | Tested |
| AuthBloc: Logout → Unauthenticated + cache cleared | ✅ PASS | Tested |
| AuthBloc: DeleteAccount → Unauthenticated + cache cleared | ✅ PASS | Tested |
| AuthInterceptor: injects Bearer token on every request | ✅ PASS | Tested |
| AuthInterceptor: 401 → refresh → retry original request | ❌ TEST MISSING | Success path not tested — see Finding #3 |
| AuthInterceptor: refresh fails → `onTokenExpired()` callback | ✅ PASS | Tested (two scenarios: null refresh token, API failure) |
| AuthInterceptor: concurrent 401s share single refresh call | ✅ PASS | Implementation correct via `_isRefreshing` lock; test not present |
| go_router auth guard — unauthenticated → `/login` | ✅ PASS | Guard in `createRouter()` redirect function |
| go_router auth guard — authenticated → `/tasks` if on auth page | ✅ PASS | |
| Deep link `tasknibbles://reset-password?token=` opens reset screen | ✅ PASS | Android manifest configured; go_router reads `token` query param |
| `ConnectivityCubit`: offline → `ConnectivityStatus.disconnected` | ✅ PASS | (tests present in connectivity_cubit_test.dart) |
| Offline banner visible when disconnected, hidden when connected | ✅ PASS | `AnimatedContainer` with 0↔36px height animation |
| Gamification hero shows placeholder (no crash) | ✅ PASS | Static `GamificationWelcome` content rendered |
| Logout clears token storage | ✅ PASS | `AuthRepository.logout()` calls `tokenStorage.clearTokens()` |
| Delete account flow: confirmation dialog → `DELETE /auth/account` | ✅ PASS | Per AuthBloc `_onDeleteAccountRequested` |

---

## Security Checklist

| Check | Result |
|:------|:-------|
| No `SharedPreferences` import anywhere in production Dart code | ✅ PASS |
| TokenStorage is the ONLY class that reads tokens | ✅ PASS — enforced by doc comment + no direct imports |
| `AuthInterceptor` is the ONLY class calling `tokenStorage.getAccessToken()` at runtime | ✅ PASS |
| iOS Keychain / Android Keystore — `encryptedSharedPreferences: true` for Android | ✅ PASS |
| Refresh token cleared from storage on failed refresh | ✅ PASS — `tokenStorage.clearTokens()` in `_tryRefreshToken` catch |
| No tokens logged in production code | ✅ PASS — only `kDebugMode` dev.log for refresh failures |

---

## Findings

### Finding #1 — MINOR: `uni_links` in pubspec but never imported in any Dart file (NON-BLOCKING)

**Observed:** `uni_links: ^0.5.1` is listed in `pubspec.yaml` and `pubspec.lock`, but `grep -rn "uni_links" lib/` returns zero results. Deep linking is handled entirely by go_router's native Android/iOS deep link integration, which is configured via the Android manifest `intent-filter` for the `tasknibbles://` scheme.

**Risk:** `uni_links` has had no new releases since 2021 and may have compatibility issues with newer Android/Gradle versions. Its successor is `app_links`.

**Recommended action:**
```yaml
# Remove from pubspec.yaml:
uni_links: ^0.5.1  # DELETE
```

go_router handles `tasknibbles://reset-password?token=...` deep links natively — no additional package is needed.

**Verdict:** NON-BLOCKING. Remove in the same commit as any bug fix or in next sprint touchpoint.

---

### Finding #2 — INFORMATIONAL: `skipAuthInterceptor` extra set but never checked (DEAD CODE)

**File:** `core/api/interceptors/auth_interceptor.dart`, line 120

**Observed:**
```dart
options: Options(
  extra: {'skipAuthInterceptor': true},  // ← set but never read
),
```

The interceptor comment says "Skip this interceptor to avoid recursive loop" but `onRequest` never reads `options.extra['skipAuthInterceptor']`. The actual infinite-loop guard is the path check at line 57:
```dart
if (err.requestOptions.path.contains('/auth/refresh')) {
  return handler.next(err);
}
```

The path guard is correct and sufficient. The `extra` field is dead documentation intent.

**Verdict:** INFORMATIONAL. Either remove the extra or add the check to `onRequest`. No functional impact.

---

### Finding #3 — MINOR: Required test "401 → refresh → retry success" missing from interceptor tests (NON-BLOCKING)

**Required by SPR-001-MB testing table:**
> `AuthInterceptor: 401 → refresh → retry` — Unit (mocktail) ✅ Required

**Observed:** `auth_interceptor_test.dart` covers the failure paths (null refresh token, API failure) but does NOT test the success path where:
1. Request gets 401
2. Interceptor refreshes token successfully
3. Original request is retried with the new token and resolves

**Expected test shape:**
```dart
test('401 → refresh succeeds → retries original request', () async {
  when(() => mockTokenStorage.getRefreshToken())
      .thenAnswer((_) async => 'old-refresh');
  when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data'), options: any(named: 'options')))
      .thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
        statusCode: 200,
        data: {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
      ));
  when(() => mockTokenStorage.saveTokens(accessToken: any(named: 'accessToken'), refreshToken: any(named: 'refreshToken')))
      .thenAnswer((_) async {});
  when(() => mockTokenStorage.getAccessToken()).thenAnswer((_) async => 'new-access');
  when(() => mockDio.fetch(any())).thenAnswer((_) async => Response(
    requestOptions: RequestOptions(path: '/api/v1/tasks'),
    statusCode: 200,
  ));

  final err = DioException(
    requestOptions: RequestOptions(path: '/api/v1/tasks'),
    response: Response(requestOptions: RequestOptions(path: '/api/v1/tasks'), statusCode: 401),
  );

  bool resolved = false;
  await interceptor.onError(err, _MockErrorHandler(onResolve: (_) => resolved = true));
  expect(resolved, isTrue);
  expect(tokenExpiredCalled, isFalse);
});
```

**Verdict:** NON-BLOCKING but **should be added before SPR-002-MB begins**. The interceptor is shared infrastructure for all future sprints; confidence in the retry path matters. File as **MB-001** in BCK-001.

---

## Architecture Compliance

| Check | Result |
|:------|:-------|
| Feature-first directory structure per BLU-004 §2 | ✅ PASS |
| `GamificationCubit.refresh()` correctly a no-op stub for Sprint 1 | ✅ PASS |
| `TaskCache.clear()` called on both logout AND token expiry | ✅ PASS |
| `SettingsCubit` is NOT a singleton — created per-screen (correct, it delegates to AuthBloc singleton) | ✅ PASS |
| `AppRoutes` constant class prevents bare string paths in feature code | ✅ PASS |
| `_isAuthPath()` helper — correct set of auth routes listed | ✅ PASS |
| `ConnectivityCubit.close()` cancels stream subscription | ✅ PASS |
| System dark/light theme supported via `ThemeMode.system` | ✅ PASS |
| `debugShowCheckedModeBanner: false` | ✅ PASS |

---

## New BCK Items from This Audit

| BCK ID | Task | Priority | Sprint |
|:-------|:-----|:---------|:-------|
| MB-001 | Add `AuthInterceptor: 401 → refresh → retry success` unit test | Medium | Before SPR-002-MB |
| MB-002 | Remove `uni_links` from pubspec.yaml (dead dependency) | Low | SPR-002-MB or hotfix |

---

## Merge Instructions

1. Merge `feature/M-001-mobile-scaffold` → `develop` (no BE conflicts — only `mobile/` directory)
2. Add MB-001 (interceptor test) as first task in SPR-002-MB
3. Proceed to assign SPR-002-MB — all preconditions are met once staging has SPR-002-BE endpoints live

---

## Decision

**APPROVED WITH NOTES — merge to `develop` immediately.**

No blocking findings. The scaffold is solid, the auth architecture is correct, and token security is properly enforced. SPR-002-MB is now unblocked.
