import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Five health states mapped to 20-point score ranges.
enum CompanionHealth {
  thriving, // 80-100
  healthy, // 60-79
  neutral, // 40-59
  struggling, // 20-39
  withering; // 0-19

  static CompanionHealth fromScore(int score) {
    if (score >= 80) return CompanionHealth.thriving;
    if (score >= 60) return CompanionHealth.healthy;
    if (score >= 40) return CompanionHealth.neutral;
    if (score >= 20) return CompanionHealth.struggling;
    return CompanionHealth.withering;
  }

  Color get primaryColor => switch (this) {
        CompanionHealth.thriving => const Color(0xFF00C853),
        CompanionHealth.healthy => const Color(0xFF66BB6A),
        CompanionHealth.neutral => const Color(0xFF78909C),
        CompanionHealth.struggling => const Color(0xFFFFA726),
        CompanionHealth.withering => const Color(0xFF8D6E63),
      };

  String get label => switch (this) {
        CompanionHealth.thriving => 'Thriving',
        CompanionHealth.healthy => 'Healthy',
        CompanionHealth.neutral => 'Neutral',
        CompanionHealth.struggling => 'Struggling',
        CompanionHealth.withering => 'Withering',
      };
}

// ── Sprite A: Round Nibbler ───────────────────────────────────────────────────
// A friendly round blob that bounces, glows, and grows sadder as health drops.

class SpriteAWidget extends StatefulWidget {
  const SpriteAWidget({super.key, required this.healthScore, this.size = 100});
  final int healthScore;
  final double size;

  @override
  State<SpriteAWidget> createState() => _SpriteAWidgetState();
}

class _SpriteAWidgetState extends State<SpriteAWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _durationFor(CompanionHealth.fromScore(widget.healthScore)),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  Duration _durationFor(CompanionHealth h) => switch (h) {
        CompanionHealth.thriving => const Duration(milliseconds: 500),
        CompanionHealth.healthy => const Duration(milliseconds: 700),
        CompanionHealth.neutral => const Duration(milliseconds: 1000),
        CompanionHealth.struggling => const Duration(milliseconds: 1400),
        CompanionHealth.withering => const Duration(milliseconds: 2200),
      };

  @override
  void didUpdateWidget(SpriteAWidget old) {
    super.didUpdateWidget(old);
    if (old.healthScore != widget.healthScore) {
      _ctrl.duration =
          _durationFor(CompanionHealth.fromScore(widget.healthScore));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = CompanionHealth.fromScore(widget.healthScore);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _SpriteAPainter(t: _anim.value, health: health),
      ),
    );
  }
}

class _SpriteAPainter extends CustomPainter {
  const _SpriteAPainter({required this.t, required this.health});
  final double t; // 0→1 animation progress
  final CompanionHealth health;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.35;
    final color = health.primaryColor;

    // Body bounce / droop
    final bounceY = switch (health) {
      CompanionHealth.thriving => -12 * t,
      CompanionHealth.healthy => -7 * t,
      CompanionHealth.neutral => -3 * t,
      CompanionHealth.struggling => 3 * math.sin(t * math.pi),
      CompanionHealth.withering => 2 * t,
    };
    final scale = switch (health) {
      CompanionHealth.thriving => 1.0 + 0.08 * t,
      CompanionHealth.healthy => 1.0 + 0.04 * t,
      CompanionHealth.neutral => 1.0,
      CompanionHealth.struggling => 1.0 - 0.04 * t,
      CompanionHealth.withering => 0.88,
    };

    canvas.save();
    canvas.translate(cx, cy + bounceY);
    canvas.scale(scale);

    // Glow
    if (health.index <= 1) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.18 + 0.12 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(Offset.zero, r * 1.25, glowPaint);
    }

    // Body
    final bodyPaint = Paint()..color = color;
    canvas.drawCircle(Offset.zero, r, bodyPaint);

    // Highlight
    final hlPaint = Paint()..color = Colors.white.withOpacity(0.35);
    canvas.drawCircle(Offset(-r * 0.28, -r * 0.28), r * 0.22, hlPaint);

    // Eyes — position shifts by mood
    final eyeY = switch (health) {
      CompanionHealth.thriving || CompanionHealth.healthy => -r * 0.15,
      CompanionHealth.neutral => -r * 0.1,
      _ => r * 0.05,
    };
    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = Colors.black87;
    for (final ex in [-r * 0.28, r * 0.28]) {
      canvas.drawCircle(Offset(ex, eyeY), r * 0.18, eyePaint);
      canvas.drawCircle(Offset(ex, eyeY + r * 0.03), r * 0.1, pupilPaint);
    }

    // Mouth
    final mouthPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (health) {
      case CompanionHealth.thriving || CompanionHealth.healthy:
        // Big smile
        path.moveTo(-r * 0.32, r * 0.18);
        path.quadraticBezierTo(0, r * 0.45, r * 0.32, r * 0.18);
      case CompanionHealth.neutral:
        // Straight
        path.moveTo(-r * 0.25, r * 0.25);
        path.lineTo(r * 0.25, r * 0.25);
      case CompanionHealth.struggling:
        // Slight frown
        path.moveTo(-r * 0.28, r * 0.30);
        path.quadraticBezierTo(0, r * 0.15, r * 0.28, r * 0.30);
      case CompanionHealth.withering:
        // Deep frown
        path.moveTo(-r * 0.32, r * 0.38);
        path.quadraticBezierTo(0, r * 0.16, r * 0.32, r * 0.38);
    }
    canvas.drawPath(path, mouthPaint);

    // Sparkles for thriving state
    if (health == CompanionHealth.thriving) {
      _drawSparkle(canvas, Offset(r * 0.9, -r * 0.7), r * 0.12, t, color);
      _drawSparkle(canvas, Offset(-r * 0.85, -r * 0.6), r * 0.09, 1 - t, color);
    }

    // Tears for withering state
    if (health == CompanionHealth.withering) {
      final tearPaint = Paint()..color = const Color(0xFF90CAF9);
      final tearY = r * 0.1 + 10 * t;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(-r * 0.32, tearY), width: r * 0.12, height: r * 0.19),
        tearPaint,
      );
    }

    canvas.restore();
  }

  void _drawSparkle(Canvas canvas, Offset pos, double size, double t, Color color) {
    final paint = Paint()
      ..color = color.withOpacity(0.6 + 0.4 * t)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 + t * math.pi;
      canvas.drawLine(
        pos,
        pos + Offset(math.cos(angle) * size, math.sin(angle) * size),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpriteAPainter old) =>
      old.t != t || old.health != health;
}

// ── Sprite B: Star Flare ──────────────────────────────────────────────────────
// A radiant star/sun shape that pulses with light, dims as health drops.

class SpriteBWidget extends StatefulWidget {
  const SpriteBWidget({super.key, required this.healthScore, this.size = 100});
  final int healthScore;
  final double size;

  @override
  State<SpriteBWidget> createState() => _SpriteBWidgetState();
}

class _SpriteBWidgetState extends State<SpriteBWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = CompanionHealth.fromScore(widget.healthScore);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _SpriteBPainter(t: _anim.value, health: health),
      ),
    );
  }
}

class _SpriteBPainter extends CustomPainter {
  const _SpriteBPainter({required this.t, required this.health});
  final double t;
  final CompanionHealth health;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.28;
    final color = health.primaryColor;

    final pulseScale = switch (health) {
      CompanionHealth.thriving => 1.0 + 0.12 * t,
      CompanionHealth.healthy => 1.0 + 0.07 * t,
      CompanionHealth.neutral => 1.0 + 0.03 * t,
      CompanionHealth.struggling => 1.0,
      CompanionHealth.withering => 0.9,
    };

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(pulseScale);

    // Rays
    final numRays = switch (health) {
      CompanionHealth.thriving => 12,
      CompanionHealth.healthy => 10,
      CompanionHealth.neutral => 8,
      CompanionHealth.struggling => 6,
      CompanionHealth.withering => 4,
    };
    final rayLength = r * (0.55 + 0.25 * t);
    final rayPaint = Paint()
      ..color = color.withOpacity(health == CompanionHealth.withering ? 0.3 : 0.6 + 0.3 * t)
      ..strokeWidth = health == CompanionHealth.withering ? 1.5 : 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < numRays; i++) {
      final angle = (i / numRays) * 2 * math.pi + t * 0.4;
      final inner = Offset(math.cos(angle) * r * 1.05, math.sin(angle) * r * 1.05);
      final outer = Offset(math.cos(angle) * (r * 1.05 + rayLength),
          math.sin(angle) * (r * 1.05 + rayLength));
      canvas.drawLine(inner, outer, rayPaint);
    }

    // Core glow (thriving only)
    if (health.index <= 1) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.2 + 0.15 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(Offset.zero, r * 1.2, glowPaint);
    }

    // Core circle
    final corePaint = Paint()
      ..shader = RadialGradient(colors: [
        color.withOpacity(0.95),
        color.withOpacity(0.6),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    canvas.drawCircle(Offset.zero, r, corePaint);

    // Face
    final eyeY = switch (health) {
      CompanionHealth.withering || CompanionHealth.struggling => r * 0.05,
      _ => -r * 0.1,
    };
    final eyePaint = Paint()..color = Colors.white.withOpacity(0.9);
    final pupilPaint = Paint()..color = Colors.black87;
    for (final ex in [-r * 0.32, r * 0.32]) {
      canvas.drawCircle(Offset(ex, eyeY), r * 0.2, eyePaint);
      canvas.drawCircle(Offset(ex, eyeY + r * 0.04), r * 0.11, pupilPaint);
    }

    // Mouth
    final mouthPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final mp = Path();
    switch (health) {
      case CompanionHealth.thriving || CompanionHealth.healthy:
        mp.moveTo(-r * 0.3, r * 0.22);
        mp.quadraticBezierTo(0, r * 0.44, r * 0.3, r * 0.22);
      case CompanionHealth.neutral:
        mp.moveTo(-r * 0.22, r * 0.28);
        mp.lineTo(r * 0.22, r * 0.28);
      default:
        mp.moveTo(-r * 0.28, r * 0.36);
        mp.quadraticBezierTo(0, r * 0.20, r * 0.28, r * 0.36);
    }
    canvas.drawPath(mp, mouthPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpriteBPainter old) => old.t != t || old.health != health;
}
