import 'package:flutter/material.dart';

// ──────────────────────────────────────────────
// SkeletonCard — single animated shimmer card
// ──────────────────────────────────────────────

/// A single shimmer placeholder card (M-056).
///
/// Uses [AnimatedBuilder] + [LinearGradient] sweep — no external package.
/// Dimensions match a [TaskTile]: height=72, full-width, border-radius=12,
/// horizontal margin=16, bottom margin=12.
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({
    super.key,
    this.height = 72,
    this.width = double.infinity,
  });

  final double height;
  final double width;

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surfaceContainerHigh;

    return Container(
      height: widget.height,
      width: widget.width,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: base,
      ),
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [
                  (_shimmer.value - 0.5).clamp(0.0, 1.0),
                  _shimmer.value.clamp(0.0, 1.0),
                  (_shimmer.value + 0.5).clamp(0.0, 1.0),
                ],
                colors: [base, highlight, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────
// TaskListSkeleton — 6-card list placeholder
// ──────────────────────────────────────────────

/// Displayed in [TaskListScreen] while BLoC is in [TaskListLoading] state (M-056).
/// Replaces the generic [CircularProgressIndicator].
class TaskListSkeleton extends StatelessWidget {
  const TaskListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: 6,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
