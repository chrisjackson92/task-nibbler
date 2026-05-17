import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/gamification_cubit.dart';
import '../data/gamification_repository.dart';
import 'widgets/sprite_widget.dart';
import 'widgets/tree_widget.dart';

/// Companion selection screen — choose a sprite and a tree.
/// Accessible by tapping the sprite/tree area in the hero section.
class CompanionPickerScreen extends StatefulWidget {
  const CompanionPickerScreen({super.key});

  @override
  State<CompanionPickerScreen> createState() => _CompanionPickerScreenState();
}

class _CompanionPickerScreenState extends State<CompanionPickerScreen> {
  String _selectedSprite = 'sprite_a';
  String _selectedTree = 'tree_a';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-select current companion from loaded state.
    final state = context.read<GamificationCubit>().state;
    if (state is GamificationLoaded) {
      _selectedSprite = state.gamState.spriteType;
      _selectedTree = state.gamState.treeType;
    } else if (state is GamificationBadgeAwarded) {
      _selectedSprite = state.gamState.spriteType;
      _selectedTree = state.gamState.treeType;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<GamificationRepository>().updateCompanion(
            spriteType: _selectedSprite,
            treeType: _selectedTree,
          );
      if (!mounted) return;
      // Refresh gamification state so hero section updates immediately.
      await context.read<GamificationCubit>().loadState();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save companion selection.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const previewScore = 80; // always show thriving preview in picker
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Companion'),
        actions: [
          TextButton(
            key: const Key('companion_picker_save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(title: 'Your Sprite', emoji: '🐾'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CompanionCard(
                key: const Key('companion_sprite_a'),
                label: 'Round Nibbler',
                selected: _selectedSprite == 'sprite_a',
                onTap: () => setState(() => _selectedSprite = 'sprite_a'),
                child: const SpriteAWidget(healthScore: previewScore, size: 80),
              ),
              _CompanionCard(
                key: const Key('companion_sprite_b'),
                label: 'Star Flare',
                selected: _selectedSprite == 'sprite_b',
                onTap: () => setState(() => _selectedSprite = 'sprite_b'),
                child: const SpriteBWidget(healthScore: previewScore, size: 80),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionHeader(title: 'Your Tree', emoji: '🌱'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CompanionCard(
                key: const Key('companion_tree_a'),
                label: 'Round Oak',
                selected: _selectedTree == 'tree_a',
                onTap: () => setState(() => _selectedTree = 'tree_a'),
                child: const TreeAWidget(healthScore: previewScore, size: 90),
              ),
              _CompanionCard(
                key: const Key('companion_tree_b'),
                label: 'Crystal Pine',
                selected: _selectedTree == 'tree_b',
                onTap: () => setState(() => _selectedTree = 'tree_b'),
                child: const TreeBWidget(healthScore: previewScore, size: 90),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Companions grow happier as you keep your streak and complete tasks. '
            'Their appearance changes across 5 health states.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.emoji});
  final String title;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.outline;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color,
            width: selected ? 2.5 : 1.5,
          ),
          color: selected
              ? theme.colorScheme.primaryContainer.withOpacity(0.25)
              : Colors.transparent,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 12,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 6),
              Icon(Icons.check_circle_rounded,
                  color: theme.colorScheme.primary, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
