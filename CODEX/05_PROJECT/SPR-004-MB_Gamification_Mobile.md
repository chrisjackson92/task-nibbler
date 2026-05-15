---
id: SPR-004-MB
title: "Sprint 4 — Gamification Mobile"
type: sprint
status: READY
assignee: coder
agent_boot: AGT-002-MB_Mobile_Developer_Agent.md
sprint_number: 4
track: mobile
estimated_days: 5
blocked_by: none — SPR-003-MB MERGED ✅, SPR-004-BE MERGED ✅, Rive stub policy covers missing .riv files
related: [BLU-004, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-15
---

> **BLUF:** Replace all gamification placeholders with live data and Rive animations. Implement the full gamification detail screen, badge shelf, badge award celebration overlay, and wire the home screen hero to real API data.

> [!CAUTION]
> **HARD DEPENDENCY:** `sprite.riv` and `tree.riv` files must exist in `assets/animations/` before this sprint can start. See PRJ-001 §9 Open Decision #2. If Rive files are not available, the Rive implementation must be stubbed — do NOT block on asset creation for the rest of the sprint logic.

# Sprint 4-MB — Gamification Mobile

---

## Pre-Conditions

- [x] `SPR-003-MB` Architect audit PASSED — merged `develop` @ `b5688c2`
- [x] `SPR-004-BE` complete — `/gamification/state` and `/gamification/badges` live on staging
- [ ] Read `PRJ-001` §5.5 (full gamification spec including hero section) in full
- [ ] Read `BLU-004_Frontend_Architecture.md` §§7–8 (Rive specs + home screen layout) in full
- [ ] Read `BLU-002-SD_Seed_Data_Reference.md` §3 (badge award trigger reference) in full
- [ ] **Rive files:** If `assets/animations/sprite.riv` and `tree.riv` are NOT present, proceed with animated colour-block placeholder. Do NOT block sprint on asset creation.

---

## Exit Criteria

- [ ] `GET /gamification/state` called on app open; hero section shows real streak + tree health
- [ ] Sprite widget renders correct Rive state (WELCOME/HAPPY/NEUTRAL/SAD) or placeholder
- [ ] Tree widget renders correct Rive state (THRIVING/HEALTHY/STRUGGLING/WITHERING) or placeholder
- [ ] Hero section on home screen is collapsible (collapses on scroll, expands at top)
- [ ] Tapping hero navigates to full gamification detail screen
- [ ] Gamification detail screen: full-size tree + streak counter + tree health bar + badge shelf
- [ ] Badge shelf: all 14 badges shown; earned in colour with `earned_at` date; locked greyed out
- [ ] Badge award overlay animates when `badges_awarded` non-empty in task completion response
- [ ] Grace day ⚡ indicator visible in hero when `grace_active: true`
- [ ] WELCOME state: sprite shows encouraging welcome animation, no score displayed
- [ ] `fvm flutter test` passes, ≥ 70% GamificationCubit coverage

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| M-030 | Gamification detail screen | Full tree, streak, tree health bar, badge shelf |
| M-031 | Rive sprite companion widget (4 states) | WELCOME/HAPPY/NEUTRAL/SAD; use placeholder if .riv missing |
| M-032 | Rive tree animation widget (4 states) | THRIVING/HEALTHY/STRUGGLING/WITHERING; placeholder if .riv missing |
| M-033 | Badge shelf widget | Grid layout; earned = coloured + emoji + date; locked = greyed |
| M-034 | Badge award overlay (celebration animation on badge unlock) | Overlay on top of task list; dismiss on tap |
| M-035 | Streak counter + grace ⚡ indicator in hero section | Grace indicator: yellow lightning bolt icon |

---

## Technical Notes

### GamificationCubit (Replace Sprint 1 Placeholder)
```dart
class GamificationCubit extends Cubit<GamificationState> {
  final GamificationRepository _repo;

  GamificationCubit(this._repo) : super(GamificationInitial());

  Future<void> loadState() async {
    emit(GamificationLoading());
    try {
      final state = await _repo.getState();
      emit(GamificationLoaded(state));
    } on DioException catch (e) {
      emit(GamificationError(_mapError(e)));
    }
  }

  void applyDelta(GamificationDelta delta) {
    if (state is GamificationLoaded) {
      final current = (state as GamificationLoaded).gamState;
      emit(GamificationLoaded(current.applyDelta(delta)));
      if (delta.badgesAwarded.isNotEmpty) {
        emit(GamificationBadgeAwarded(delta.badgesAwarded.first)); // show overlay
      }
    }
  }
}
```

### Rive Widget Pattern (see BLU-004 §7)
```dart
// If sprite.riv is available:
RiveAnimation.asset(
  'assets/animations/sprite.riv',
  stateMachines: ['SpriteSM'],
  onInit: (artboard) {
    final ctrl = StateMachineController.fromArtboard(artboard, 'SpriteSM')!;
    artboard.addController(ctrl);
    // Drive state from GamificationCubit
  },
)

// If sprite.riv is NOT available (placeholder):
Container(
  height: 120,
  color: _spriteColor(spriteState),  // GREEN/YELLOW/BLUE/GREY
  child: Center(child: Text(spriteState.name, style: style)),
)
```

### Hero Section Collapsible Behaviour
Use `SliverAppBar` with `expandedHeight`:
```dart
CustomScrollView(
  slivers: [
    SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: false,
      flexibleSpace: FlexibleSpaceBar(
        background: BlocBuilder<GamificationCubit, GamificationState>(
          builder: (ctx, state) => HeroSection(state: state),
        ),
      ),
    ),
    SliverList(delegate: SliverChildBuilderDelegate(...)), // task list
  ],
)
```

### Badge Award Overlay
```dart
// Shown when GamificationBadgeAwarded state emitted
class BadgeAwardOverlay extends StatelessWidget {
  final Badge badge;
  // Full-screen semi-transparent overlay
  // Shows: badge.emoji (large), badge.name, badge.description
  // Dismiss: tap anywhere or auto-dismiss after 4 seconds
}
```

### Badge Shelf Grid
```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
  itemBuilder: (ctx, i) {
    final badge = allBadges[i];
    return Opacity(
      opacity: badge.earned ? 1.0 : 0.3,
      child: Column(children: [
        Text(badge.emoji, style: TextStyle(fontSize: 32)),
        Text(badge.name, style: TextStyle(fontSize: 10)),
      ]),
    );
  },
)
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `GamificationCubit: loadState success → GamificationLoaded` | Unit | ✅ |
| `GamificationCubit: applyDelta → updates streak and tree health` | Unit | ✅ |
| `GamificationCubit: applyDelta with badge → GamificationBadgeAwarded` | Unit | ✅ |
| `GamificationCubit: WELCOME state → sprite_state = WELCOME` | Unit | ✅ |
| `BadgeShelf widget: earned badge at full opacity` | Widget | ✅ |
| `BadgeShelf widget: locked badge at 0.3 opacity` | Widget | ✅ |

---

## Architect Audit Checklist

- [ ] Hero section collapses on scroll — confirmed on physical device
- [ ] Tapping hero navigates to gamification detail screen (not in-place expand)
- [ ] `applyDelta` called (not `loadState`) after task completion — no extra API round-trip
- [ ] Grace ⚡ indicator visible when `grace_active: true` in API response
- [ ] WELCOME state: no score numbers shown; friendly message displayed
- [ ] Badge overlay auto-dismisses after 4 seconds if not tapped
- [ ] All 14 badges rendered in badge shelf (count: `badges.length == 14`)
