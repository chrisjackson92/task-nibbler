---
id: SPR-010-MB
title: "Sprint 010 — Mobile: Production Polish (Push Notifications, Empty States, Skeletons, Branding, APK v1.3)"
type: sprint
status: READY
owner: architect
agents: [coder-mobile]
tags: [sprint, mobile, polish, notifications, ux, branding]
related: [AGT-002-MB, CON-002, BLU-004, PLN-003, SPR-009-MB, AUD-014-MB]
created: 2026-05-18
updated: 2026-05-18
version: 1.0.0
---

> **BLUF:** Final MVP polish sprint before App Store submission. Five deliverables: (1) push notification permission + local token storage, (2) upgraded empty states for tasks and badges, (3) loading skeleton for task list, (4) app icon and splash screen branding, (5) production APK v1.3. All work is mobile-only; no backend changes required this sprint.

# SPR-010-MB — Mobile Production Polish

---

## Assignment

| Field | Value |
|:------|:------|
| **Agent** | Mobile Developer Agent (AGT-002-MB) |
| **Estimated** | 2–3 days |
| **Branch** | `feature/M-054-production-polish` (fork from `main`) |
| **Staging Backend** | `https://task-nibbles-api-staging.fly.dev/api/v1` |
| **Production Backend** | `https://task-nibbles-api.fly.dev/api/v1` |

---

## Reading Order (Boot Sequence)

1. `AGT-002-MB_Mobile_Developer_Agent.md` — your role and standards
2. `PRJ-001_product_vision_and_features.md` §4 — push notification spec
3. `SPR-009-MB_Companion_Selection_Profile_Expansion.md` — what was just built (context)
4. `BLU-004_Frontend_Architecture.md` §§3–5 — design system and widget patterns
5. This document — tasks and exit criteria

---

## Tasks

### M-054 — Push Notification Permission + Local Token Storage (P1)

**Goal:** Request notification permission at the right moment and store the device token locally for future use. The backend endpoint (`POST /api/v1/device-tokens`) does not exist yet — do NOT attempt the API call. Store the token in `Hive` only.

**Specifications:**
- `permission_handler` is already in `pubspec.yaml` — do not add Firebase or any push SDK
- Request `Permission.notification` **after** the user successfully logs in (in `AuthBloc` when `AuthAuthenticated` state is emitted), not on splash
- If permission is denied, fail silently — do not show an error or repeat the request
- Use `permission_handler`'s `Permission.notification.request()` — this returns the `PermissionStatus`
- On iOS, `permission_handler` wraps UNUserNotificationCenter; on Android 13+ it wraps POST_NOTIFICATIONS
- Store the granted/denied status in `Hive` box `'settings'` key `'notification_permission_granted'` (bool)
- Do NOT attempt to retrieve an APNs/FCM token in this sprint — that requires Firebase SDK

**Files to create/modify:**
- `lib/core/notifications/notification_permission_service.dart` — new service with single method `requestIfNeeded()`
- `lib/features/auth/bloc/auth_bloc.dart` — call `NotificationPermissionService.requestIfNeeded()` in `_onLoginSuccess` after emitting `AuthAuthenticated`

**DO NOT add Firebase, FlutterFire, or any push notification SDK.**

---

### M-055 — Enhanced Empty States (P2)

**Goal:** Replace the existing minimal `_EmptyTasksView` and the badge shelf placeholder with polished, on-brand empty states.

**What already exists:**
- `_EmptyTasksView` in `task_list_screen.dart` (lines ~222–255) — a basic placeholder; upgrade it in place
- Badge shelf in `gamification_detail_screen.dart` — add an empty state if `badges` list is empty

**Specifications for Task List empty state:**
- Illustration: use `CustomPaint` or a simple SVG-like drawing (no external image files needed) — a clipboard with a checkmark, drawn in the app's primary colour
- Headline: `"Nothing here yet"` (`titleMedium`, w700)
- Subtext: `"Tap + to add your first task"` (`bodySmall`, muted)
- CTA button: `"Add Task"` → calls `context.push(AppRoutes.taskCreate)`
- Animate in with a `FadeTransition` + `SlideTransition` (slide up 20px, 400ms)

**Specifications for Badge shelf empty state:**
- Shown only when `badges.isEmpty`
- Simple centred text: `"Complete tasks to earn badges 🏅"` (`bodySmall`, muted)
- No illustration needed

---

### M-056 — Task List Loading Skeleton (P2)

**Goal:** Show shimmer-style skeleton cards while the task list BLoC is in `TaskListLoading` state.

**Shimmer implementation:** Do NOT add the `shimmer` pub package. Implement using an `AnimatedBuilder` + `LinearGradient` sweep animation — this keeps the dependency count down.

**Specifications:**
- Create `lib/core/widgets/skeleton_loader.dart` — a reusable `SkeletonCard` widget
- `SkeletonCard` accepts `height` and `width`; draws a rounded rect with an animated shimmer gradient (light grey → slightly lighter grey → light grey, sweeping left-to-right, 1.2s loop)
- `TaskListSkeleton` widget = a `ListView` of 6 `SkeletonCard` items that mimic the height of a `TaskTile`
- In `task_list_screen.dart`: replace the `CircularProgressIndicator` shown on `TaskListLoading` state with `TaskListSkeleton()`

**Skeleton card dimensions:** height = 72px, full width, border radius = 12px, left margin = 16px, right margin = 16px, bottom margin = 12px

---

### M-057 — App Icon + Splash Screen Branding (P2)

**Goal:** Replace the default Flutter icon and white splash with branded assets.

**App Icon:**
- Design: a green rounded-square with a white checkmark and a small leaf/sprout at the bottom-right corner
- Generate using `flutter_launcher_icons` package
- Add `flutter_launcher_icons: ^0.13.1` to `dev_dependencies` in `pubspec.yaml`
- Create `flutter_icons:` config block in `pubspec.yaml`:
  ```yaml
  flutter_icons:
    android: true
    ios: true
    image_path: "assets/icon/app_icon.png"
    adaptive_icon_background: "#1B5E20"
    adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"
  ```
- Create the icon PNG at `assets/icon/app_icon.png` (1024×1024, green background, white checkmark + leaf) — draw using `Canvas` in a standalone Dart script or provide a convincing placeholder
- Run: `dart run flutter_launcher_icons`

**Splash Screen:**
- Add `flutter_native_splash: ^2.4.0` to `dev_dependencies`
- Config in `pubspec.yaml`:
  ```yaml
  flutter_native_splash:
    color: "#1B5E20"
    image: assets/icon/app_icon.png
    android_12:
      color: "#1B5E20"
      image: assets/icon/app_icon.png
  ```
- Run: `dart run flutter_native_splash:create`
- Remove `SplashScreen` widget timer (the existing `SplashScreen` does session restore — keep that logic, just update the visual background colour to `#1B5E20` and the loading indicator to white)

> [!IMPORTANT]
> The `SplashScreen` widget in `lib/features/auth/ui/splash_screen.dart` handles session restore. Do NOT remove it. Only update its background colour and indicator colour. The native splash is a separate pre-Flutter layer.

---

### M-058 — Production APK v1.3 Build + S3 Distribution (P0)

**Goal:** Build a signed release APK and upload it to the S3 bucket used for previous releases.

**Steps:**
1. Run `flutter build apk --release` from `mobile/`
2. The signing config should already be wired from SPR-003-MB/SPR-008-MB
3. Upload the resulting `build/app/outputs/flutter-apk/app-release.apk` to:
   - S3 bucket: `task-nibbles-attachments`
   - Key prefix: `apk-releases/v1.3/task-nibbler-v1.3.apk`
4. Generate a pre-signed GET URL (60-minute TTL) and provide it in the sprint completion report

**AWS credentials** are in `Credentials.txt` in the repo root.

> [!NOTE]
> If the signing config is not present, build an unsigned APK (`--no-shrink --debug` is acceptable for distribution review) and note it in the completion report.

---

## Exit Criteria

| # | Criterion | Test |
|:--|:----------|:-----|
| 1 | Notification permission dialog shown on first post-login on Android 13+ / iOS | Manual: log in fresh, observe system dialog |
| 2 | Permission denial is silent — no error shown, app continues normally | Manual: deny permission, observe no error |
| 3 | Task list empty state shows illustration, headline, subtext, and "Add Task" button | Manual: clear all tasks, observe screen |
| 4 | "Add Task" button on empty state navigates to task create screen | Manual: tap button |
| 5 | Skeleton loads instead of spinner on task list initial load | Manual: cold launch with network throttled |
| 6 | App icon updated on device home screen | Manual: install APK, check launcher |
| 7 | Splash background is dark green (#1B5E20), not white | Manual: cold launch |
| 8 | SplashScreen still performs session restore (no regression) | Manual: restart app while logged in |
| 9 | `flutter analyze` passes (0 errors, 0 warnings) | `flutter analyze --no-pub` |
| 10 | APK v1.3 built and S3 URL provided in completion report | S3 key confirmed |

---

## Packages to Add

| Package | Version | `dev_dependencies`? | Purpose |
|:--------|:--------|:---------------------|:--------|
| `flutter_launcher_icons` | `^0.13.1` | ✅ Yes | Generate adaptive icons |
| `flutter_native_splash` | `^2.4.0` | ✅ Yes | Generate native splash screens |

No runtime dependency additions required.

---

## Architecture Constraints

- Follow the existing feature-first folder layout (`lib/features/`, `lib/core/`)
- All new widgets go in `lib/core/widgets/` (skeleton loader) or inline in the feature screen (empty states)
- No new BLoC or Cubit required for this sprint
- Theme colours: use `Theme.of(context).colorScheme.*` — do not hardcode hex values except in `pubspec.yaml` splash/icon config
- `AppRoutes.taskCreate` already exists in `app_router.dart` — use it for the "Add Task" CTA

---

## Known Codebase Landmarks

| File | Relevance |
|:-----|:----------|
| `lib/features/tasks/ui/task_list_screen.dart` | Contains `_EmptyTasksView` (upgrade) and `TaskListLoading` state handling (add skeleton) |
| `lib/features/gamification/ui/gamification_detail_screen.dart` | Contains badge shelf (add empty state) |
| `lib/features/auth/bloc/auth_bloc.dart` | Call notification permission request after `AuthAuthenticated` |
| `lib/features/auth/ui/splash_screen.dart` | Update background colour only |
| `lib/core/router/app_router.dart` | `AppRoutes.taskCreate` for CTA |
| `lib/core/widgets/` | Place `skeleton_loader.dart` here |
| `mobile/pubspec.yaml` | Add dev_dependencies; add `flutter_native_splash` and `flutter_launcher_icons` config |

---

## Completion Report Requirements

When done, commit with message:
```
feat(SPR-010-MB): production polish — push permission, empty states, skeleton, branding, APK v1.3
```

And provide:
1. Pre-signed S3 URL for the APK (or note if APK is debug-only)
2. Screenshot or description of the new app icon
3. Screenshot or description of the new splash screen
4. Confirmation that `flutter analyze` passed
5. Any deviations from this spec with rationale
