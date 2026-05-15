import 'package:flutter/material.dart';

/// Gamification detail screen placeholder — full Rive tree + badge shelf implemented in SPR-004-MB.
class GamificationDetailScreen extends StatelessWidget {
  const GamificationDetailScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your Garden')),
        body: const Center(
          child: Text('Gamification detail — Sprint 4'),
        ),
      );
}
