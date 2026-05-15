import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../../../core/api/models/gamification_models.dart';

/// Animated companion sprite widget (M-031).
///
/// - If `assets/animations/sprite.riv` is present, drives a Rive state machine
///   named `SpriteSM` with an input `StateInput` set to the corresponding
///   integer (0=WELCOME, 1=HAPPY, 2=NEUTRAL, 3=SAD).
/// - If the Rive file is absent or fails to load, renders a coloured container
///   placeholder so the rest of the sprint is never blocked on asset creation
///   (SPR-004-MB CAUTION note).
class SpriteWidget extends StatefulWidget {
  const SpriteWidget({super.key, required this.spriteState});

  final SpriteState spriteState;

  @override
  State<SpriteWidget> createState() => _SpriteWidgetState();
}

class _SpriteWidgetState extends State<SpriteWidget> {
  SMINumber? _stateInput;
  bool _riveError = false;

  void _onRiveInit(Artboard artboard) {
    final ctrl =
        StateMachineController.fromArtboard(artboard, 'SpriteSM');
    if (ctrl == null) {
      setState(() => _riveError = true);
      return;
    }
    artboard.addController(ctrl);
    _stateInput = ctrl.findInput<double>('StateInput') as SMINumber?;
    _updateState();
  }

  void _updateState() {
    _stateInput?.value = switch (widget.spriteState) {
      SpriteState.welcome => 0,
      SpriteState.happy => 1,
      SpriteState.neutral => 2,
      SpriteState.sad => 3,
    };
  }

  @override
  void didUpdateWidget(SpriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spriteState != widget.spriteState) _updateState();
  }

  @override
  Widget build(BuildContext context) {
    if (_riveError) return _Placeholder(spriteState: widget.spriteState);

    return RiveAnimation.asset(
      'assets/animations/sprite.riv',
      stateMachines: const ['SpriteSM'],
      fit: BoxFit.contain,
      onInit: _onRiveInit,
    );
  }
}

/// Colour-coded placeholder shown when Rive asset is not yet available.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.spriteState});
  final SpriteState spriteState;

  @override
  Widget build(BuildContext context) {
    final (bg, emoji, label) = switch (spriteState) {
      SpriteState.welcome => (const Color(0xFF81C784), '🌱', 'Welcome!'),
      SpriteState.happy => (const Color(0xFF4CAF50), '😊', 'Happy'),
      SpriteState.neutral => (const Color(0xFF90A4AE), '😐', 'Neutral'),
      SpriteState.sad => (const Color(0xFF78909C), '😢', 'Sad'),
    };

    return Container(
      decoration: BoxDecoration(
        color: bg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bg.withOpacity(0.4)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  color: bg, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
