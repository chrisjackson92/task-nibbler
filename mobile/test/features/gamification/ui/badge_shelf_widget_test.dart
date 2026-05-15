import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:task_nibbles/core/api/models/gamification_models.dart';
import 'package:task_nibbles/features/gamification/ui/widgets/badge_shelf_widget.dart';


// ── Test data ─────────────────────────────────────────────────────────────────

BadgeData _earnedBadge(String id) => BadgeData(
      id: id,
      name: 'Test Badge',
      emoji: '⭐',
      description: 'Test',
      triggerType: 'TEST',
      earned: true,
      earnedAt: DateTime(2026, 5, 15),
    );

BadgeData _lockedBadge(String id) => BadgeData(
      id: id,
      name: 'Locked Badge',
      emoji: '🔒',
      description: 'Not yet',
      triggerType: 'TEST',
      earned: false,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  Widget buildBadgeShelf(List<BadgeData> badges) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BadgeShelfWidget(badges: badges),
        ),
      ),
    );
  }

  // ── 5. BadgeShelf: earned badge at full opacity ────────────────────────────

  testWidgets(
    'earned badge tile is at full opacity (1.0)',
    (tester) async {
      await tester.pumpWidget(
          buildBadgeShelf([_earnedBadge('FIRST_NIBBLE')]));
      await tester.pump();

      // The Opacity IS the keyed widget (it wraps the tile).
      final opacity = tester.widget<Opacity>(
        find.byKey(const Key('badge_tile_FIRST_NIBBLE')),
      );
      expect(opacity.opacity, 1.0);
    },
  );

  // ── 6. BadgeShelf: locked badge at 0.3 opacity ────────────────────────────

  testWidgets(
    'locked badge tile is at 0.3 opacity',
    (tester) async {
      await tester.pumpWidget(
          buildBadgeShelf([_lockedBadge('STREAK_7')]));
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find.byKey(const Key('badge_tile_STREAK_7')),
      );
      expect(opacity.opacity, 0.3);
    },
  );
}
