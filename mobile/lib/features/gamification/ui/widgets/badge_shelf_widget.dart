import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/models/gamification_models.dart';

final _dateFormat = DateFormat('MMM d, y');

/// Badge shelf grid — shows all 14 badges in canonical display order (M-033).
///
/// Earned badges: full opacity with name + earned date.
/// Locked badges: 0.3 opacity with name only (no date).
class BadgeShelfWidget extends StatelessWidget {
  const BadgeShelfWidget({super.key, required this.badges});

  final List<BadgeData> badges;

  @override
  Widget build(BuildContext context) {
    // Sort badges into canonical display order (BLU-002-SD §2).
    final ordered = kBadgeDisplayOrder
        .map((id) => badges.firstWhere(
              (b) => b.id == id,
              orElse: () => BadgeData(
                id: id,
                name: id,
                emoji: '🔒',
                description: '',
                triggerType: '',
                earned: false,
              ),
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Badges',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${badges.where((b) => b.earned).length} / ${ordered.length} earned',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          key: const Key('badge_shelf_grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            childAspectRatio: 0.75,
          ),
          itemCount: ordered.length,
          itemBuilder: (_, i) => _BadgeTile(badge: ordered[i]),
        ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});
  final BadgeData badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      key: Key('badge_tile_${badge.id}'),
      opacity: badge.earned ? 1.0 : 0.3,
      child: Tooltip(
        message: badge.description.isNotEmpty
            ? badge.description
            : badge.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: badge.earned
                    ? const Color(0xFF4CAF50).withOpacity(0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: badge.earned
                      ? const Color(0xFF4CAF50).withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  badge.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              badge.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (badge.earned && badge.earnedAt != null)
              Text(
                _dateFormat.format(badge.earnedAt!.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
