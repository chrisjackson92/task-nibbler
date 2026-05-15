import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/api/models/gamification_models.dart';
import '../../../gamification/bloc/gamification_cubit.dart';

/// Listens to [GamificationCubit] and shows a full-screen celebration overlay
/// whenever [GamificationBadgeAwarded] is emitted (M-034).
///
/// Auto-dismisses after 4 seconds or on tap.
/// Does NOT push a new route — uses an [OverlayEntry] to stay on top of
/// whatever screen is active.
class BadgeAwardListener extends StatefulWidget {
  const BadgeAwardListener({super.key, required this.child});

  final Widget child;

  @override
  State<BadgeAwardListener> createState() => _BadgeAwardListenerState();
}

class _BadgeAwardListenerState extends State<BadgeAwardListener> {
  OverlayEntry? _entry;
  Timer? _dismissTimer;

  void _show(BuildContext context, BadgeData badge) {
    _dismiss();
    _entry = OverlayEntry(
      builder: (_) => _BadgeOverlay(
        badge: badge,
        onDismiss: _dismiss,
      ),
    );
    Overlay.of(context).insert(_entry!);
    _dismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GamificationCubit, GamificationState>(
      listenWhen: (_, curr) => curr is GamificationBadgeAwarded,
      listener: (ctx, state) {
        if (state is GamificationBadgeAwarded) {
          _show(ctx, state.badge);
        }
      },
      child: widget.child,
    );
  }
}

// ── Overlay content ───────────────────────────────────────────────────────────

class _BadgeOverlay extends StatefulWidget {
  const _BadgeOverlay({required this.badge, required this.onDismiss});
  final BadgeData badge;
  final VoidCallback onDismiss;

  @override
  State<_BadgeOverlay> createState() => _BadgeOverlayState();
}

class _BadgeOverlayState extends State<_BadgeOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          key: const Key('badge_award_overlay'),
          color: Colors.black.withOpacity(0.75),
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🏅 Badge Unlocked!',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF2E7D32),
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.badge.emoji,
                        style: const TextStyle(fontSize: 72),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.badge.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.badge.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Tap to dismiss',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black38,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
