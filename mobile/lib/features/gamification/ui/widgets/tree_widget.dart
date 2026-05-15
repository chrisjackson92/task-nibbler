import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../../../core/api/models/gamification_models.dart';

/// Animated tree widget (M-032).
///
/// - If `assets/animations/tree.riv` is present, drives a Rive state machine
///   named `TreeSM` with an input `HealthInput` mapped to the health score (0–100).
/// - Falls back to a colour-coded placeholder if the asset is missing.
class TreeWidget extends StatefulWidget {
  const TreeWidget({
    super.key,
    required this.treeState,
    required this.healthScore,
  });

  final TreeState treeState;
  final int healthScore; // 0–100

  @override
  State<TreeWidget> createState() => _TreeWidgetState();
}

class _TreeWidgetState extends State<TreeWidget> {
  SMINumber? _healthInput;
  bool _riveError = false;

  void _onRiveInit(Artboard artboard) {
    final ctrl = StateMachineController.fromArtboard(artboard, 'TreeSM');
    if (ctrl == null) {
      setState(() => _riveError = true);
      return;
    }
    artboard.addController(ctrl);
    _healthInput = ctrl.findInput<double>('HealthInput') as SMINumber?;
    _updateHealth();
  }

  void _updateHealth() {
    _healthInput?.value = widget.healthScore.toDouble();
  }

  @override
  void didUpdateWidget(TreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.healthScore != widget.healthScore) _updateHealth();
  }

  @override
  Widget build(BuildContext context) {
    if (_riveError) {
      return _TreePlaceholder(
          treeState: widget.treeState, healthScore: widget.healthScore);
    }

    return RiveAnimation.asset(
      'assets/animations/tree.riv',
      stateMachines: const ['TreeSM'],
      fit: BoxFit.contain,
      onInit: _onRiveInit,
    );
  }
}

class _TreePlaceholder extends StatelessWidget {
  const _TreePlaceholder(
      {required this.treeState, required this.healthScore});
  final TreeState treeState;
  final int healthScore;

  @override
  Widget build(BuildContext context) {
    final (bg, emoji, label) = switch (treeState) {
      TreeState.thriving => (const Color(0xFF2E7D32), '🌳', 'Thriving'),
      TreeState.healthy => (const Color(0xFF4CAF50), '🌿', 'Healthy'),
      TreeState.struggling => (const Color(0xFFF9A825), '🍂', 'Struggling'),
      TreeState.withering => (const Color(0xFF8D6E63), '🪨', 'Withering'),
    };

    return Container(
      decoration: BoxDecoration(
        color: bg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: bg,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          // Health bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const Key('tree_health_bar'),
                value: healthScore / 100,
                minHeight: 6,
                backgroundColor: bg.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(bg),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$healthScore / 100',
            style: TextStyle(
                color: bg.withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
