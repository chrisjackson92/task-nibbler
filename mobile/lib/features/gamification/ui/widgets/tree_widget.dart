import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'sprite_widget.dart' show CompanionHealth;

// ── Tree A: Round Oak ─────────────────────────────────────────────────────────
// A friendly oak tree with a swaying crown. Crown shrinks and changes colour
// as health drops; new leaves float up when thriving.

class TreeAWidget extends StatefulWidget {
  const TreeAWidget({super.key, required this.healthScore, this.size = 120});
  final int healthScore;
  final double size;

  @override
  State<TreeAWidget> createState() => _TreeAWidgetState();
}

class _TreeAWidgetState extends State<TreeAWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
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
        painter: _TreeAPainter(t: _anim.value, health: health),
      ),
    );
  }
}

class _TreeAPainter extends CustomPainter {
  const _TreeAPainter({required this.t, required this.health});
  final double t;
  final CompanionHealth health;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height * 0.88;
    final trunkH = size.height * 0.30;
    final crownR = size.width * _crownScale;

    // Trunk
    final trunkPaint = Paint()..color = const Color(0xFF795548);
    final trunkW = size.width * 0.09;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - trunkW / 2, baseY - trunkH, trunkW, trunkH),
        const Radius.circular(4),
      ),
      trunkPaint,
    );

    // Sway (gentle for healthy, almost none for withering)
    final swayAngle = switch (health) {
      CompanionHealth.thriving => 0.04 * math.sin(t * math.pi),
      CompanionHealth.healthy => 0.03 * math.sin(t * math.pi),
      CompanionHealth.neutral => 0.015 * math.sin(t * math.pi),
      CompanionHealth.struggling => 0.008 * math.sin(t * math.pi),
      CompanionHealth.withering => 0.004 * math.sin(t * math.pi),
    };

    canvas.save();
    canvas.translate(cx, baseY - trunkH);
    canvas.rotate(swayAngle);

    // Ground shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, trunkH), width: crownR * 1.6, height: crownR * 0.3),
      shadowPaint,
    );

    // Crown layers (depth effect)
    for (int layer = 2; layer >= 0; layer--) {
      final layerOffset = Offset(0, -crownR * (0.1 + layer * 0.18));
      final layerR = crownR * (1.0 - layer * 0.15);
      final layerColor = _crownColor(layer);
      final crownPaint = Paint()..color = layerColor;
      canvas.drawCircle(layerOffset, layerR, crownPaint);
    }

    // Rising leaves for thriving state
    if (health == CompanionHealth.thriving) {
      _drawLeaf(canvas, Offset(-crownR * 0.5, -crownR * 1.6 - 12 * t), 0.6 + t);
      _drawLeaf(canvas, Offset(crownR * 0.4, -crownR * 1.8 - 18 * t), 1.0 - t);
    }

    // Falling leaves for struggling/withering
    if (health == CompanionHealth.struggling || health == CompanionHealth.withering) {
      _drawFallingLeaf(canvas, Offset(-crownR * 0.3 + 6 * t, crownR * 0.2 + 14 * t), t);
      _drawFallingLeaf(canvas, Offset(crownR * 0.4 - 4 * t, crownR * 0.4 + 10 * t), 1 - t);
    }

    canvas.restore();
  }

  double get _crownScale => switch (health) {
        CompanionHealth.thriving => 0.38,
        CompanionHealth.healthy => 0.34,
        CompanionHealth.neutral => 0.29,
        CompanionHealth.struggling => 0.24,
        CompanionHealth.withering => 0.18,
      };

  Color _crownColor(int layer) {
    final colors = switch (health) {
      CompanionHealth.thriving => [
          const Color(0xFF1B5E20),
          const Color(0xFF2E7D32),
          const Color(0xFF388E3C),
        ],
      CompanionHealth.healthy => [
          const Color(0xFF2E7D32),
          const Color(0xFF43A047),
          const Color(0xFF66BB6A),
        ],
      CompanionHealth.neutral => [
          const Color(0xFF558B2F),
          const Color(0xFF7CB342),
          const Color(0xFF9CCC65),
        ],
      CompanionHealth.struggling => [
          const Color(0xFFE65100),
          const Color(0xFFEF6C00),
          const Color(0xFFFFA726),
        ],
      CompanionHealth.withering => [
          const Color(0xFF4E342E),
          const Color(0xFF6D4C41),
          const Color(0xFF8D6E63),
        ],
    };
    return colors[layer.clamp(0, 2)];
  }

  void _drawLeaf(Canvas canvas, Offset pos, double opacity) {
    final lp = Paint()..color = const Color(0xFF81C784).withOpacity(opacity.clamp(0.0, 1.0));
    canvas.drawOval(
      Rect.fromCenter(center: pos, width: 8, height: 14),
      lp,
    );
  }

  void _drawFallingLeaf(Canvas canvas, Offset pos, double t) {
    final lp = Paint()
      ..color = const Color(0xFFF9A825).withOpacity((1 - t).clamp(0.0, 1.0));
    canvas.drawOval(
      Rect.fromCenter(center: pos, width: 7, height: 12),
      lp,
    );
  }

  @override
  bool shouldRepaint(_TreeAPainter old) => old.t != t || old.health != health;
}

// ── Tree B: Crystal Pine ──────────────────────────────────────────────────────
// An angular crystal pine with glowing tips. Shimmers when thriving,
// goes dark and still when withering.

class TreeBWidget extends StatefulWidget {
  const TreeBWidget({super.key, required this.healthScore, this.size = 120});
  final int healthScore;
  final double size;

  @override
  State<TreeBWidget> createState() => _TreeBWidgetState();
}

class _TreeBWidgetState extends State<TreeBWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
        painter: _TreeBPainter(t: _anim.value, health: health),
      ),
    );
  }
}

class _TreeBPainter extends CustomPainter {
  const _TreeBPainter({required this.t, required this.health});
  final double t;
  final CompanionHealth health;

  static const _tierColors = {
    CompanionHealth.thriving: [Color(0xFF00BCD4), Color(0xFF26C6DA), Color(0xFF80DEEA)],
    CompanionHealth.healthy: [Color(0xFF00897B), Color(0xFF26A69A), Color(0xFF80CBC4)],
    CompanionHealth.neutral: [Color(0xFF455A64), Color(0xFF607D8B), Color(0xFF90A4AE)],
    CompanionHealth.struggling: [Color(0xFF37474F), Color(0xFF546E7A), Color(0xFF78909C)],
    CompanionHealth.withering: [Color(0xFF263238), Color(0xFF37474F), Color(0xFF455A64)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height * 0.90;
    final h = size.height * 0.75;
    final colors = _tierColors[health]!;

    // Trunk
    final trunkPaint = Paint()..color = const Color(0xFF546E7A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 5, baseY - h * 0.18, 10, h * 0.18),
        const Radius.circular(3),
      ),
      trunkPaint,
    );

    // Bob offset
    final bobY = switch (health) {
      CompanionHealth.thriving => -6 * t,
      CompanionHealth.healthy => -4 * t,
      CompanionHealth.neutral => -2 * t,
      _ => 0.0,
    };

    canvas.save();
    canvas.translate(cx, baseY - h * 0.18 + bobY);

    // 3 tiers (bottom/middle/top)
    final tierRatios = [0.72, 0.50, 0.32];
    final tierYOffsets = [-h * 0.0, -h * 0.28, -h * 0.52];
    for (int i = 0; i < 3; i++) {
      final w = h * tierRatios[i];
      final ty = tierYOffsets[i].toDouble();
      final col = colors[i];
      final fill = Paint()..color = col.withOpacity(health == CompanionHealth.withering ? 0.4 : 0.85);
      final path = Path()
        ..moveTo(0, ty - h * 0.22)
        ..lineTo(w / 2, ty)
        ..lineTo(-w / 2, ty)
        ..close();
      canvas.drawPath(path, fill);

      // Glowing tips for thriving
      if (health == CompanionHealth.thriving || health == CompanionHealth.healthy) {
        final glowPaint = Paint()
          ..color = col.withOpacity(0.3 + 0.25 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(Offset(0, ty - h * 0.22), 6 + 4 * t, glowPaint);
        final tipPaint = Paint()..color = Colors.white.withOpacity(0.7 + 0.3 * t);
        canvas.drawCircle(Offset(0, ty - h * 0.22), 3, tipPaint);
      }
    }

    // Sparkle particles for thriving
    if (health == CompanionHealth.thriving) {
      for (final offset in [
        Offset(-h * 0.28, -h * 0.15),
        Offset(h * 0.26, -h * 0.28),
        Offset(-h * 0.18, -h * 0.48),
      ]) {
        final p = Paint()
          ..color = Colors.white.withOpacity(0.5 + 0.5 * t)
          ..strokeWidth = 1.5;
        canvas.drawCircle(offset, 2 + 2 * t, p);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_TreeBPainter old) => old.t != t || old.health != health;
}
