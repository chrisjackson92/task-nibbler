import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../../auth/data/auth_repository.dart';

/// Edit profile screen — timezone only for now.
/// Accessible via Settings → edit icon on account tile.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _tzCtrl;
  bool _saving = false;
  String? _error;

  // Common IANA timezones ordered by region for the picker list.
  static const _commonTimezones = [
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Phoenix',
    'America/Anchorage',
    'Pacific/Honolulu',
    'America/Toronto',
    'America/Vancouver',
    'America/Sao_Paulo',
    'America/Buenos_Aires',
    'America/Mexico_City',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Madrid',
    'Europe/Rome',
    'Europe/Amsterdam',
    'Europe/Moscow',
    'Africa/Cairo',
    'Africa/Johannesburg',
    'Africa/Lagos',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Dhaka',
    'Asia/Bangkok',
    'Asia/Singapore',
    'Asia/Hong_Kong',
    'Asia/Shanghai',
    'Asia/Tokyo',
    'Asia/Seoul',
    'Australia/Sydney',
    'Australia/Melbourne',
    'Pacific/Auckland',
  ];

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    final currentTz =
        authState is AuthAuthenticated ? authState.user.timezone : 'UTC';
    _tzCtrl = TextEditingController(text: currentTz);
  }

  @override
  void dispose() {
    _tzCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTimezone() async {
    final selected = await showSearch<String?>(
      context: context,
      delegate: _TimezoneSearchDelegate(_commonTimezones),
    );
    if (selected != null && mounted) {
      _tzCtrl.text = selected;
      setState(() => _error = null);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      final updatedUser = await repo.updateTimezone(_tzCtrl.text.trim());
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthProfileUpdated(user: updatedUser));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to update profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            key: const Key('edit_profile_save_button'),
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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Timezone',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('edit_profile_timezone_picker'),
            onTap: _pickTimezone,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _error != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tzCtrl.text.isEmpty ? 'Select timezone' : _tzCtrl.text,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Timezone affects how due dates and recurring task resets are calculated.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timezone search delegate ──────────────────────────────────────────────────

class _TimezoneSearchDelegate extends SearchDelegate<String?> {
  _TimezoneSearchDelegate(this.timezones);

  final List<String> timezones;

  @override
  String get searchFieldLabel => 'Search timezone…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = query.isEmpty
        ? timezones
        : timezones
            .where((tz) => tz.toLowerCase().contains(query.toLowerCase()))
            .toList();

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.schedule_outlined),
        title: Text(filtered[i]),
        onTap: () => close(context, filtered[i]),
      ),
    );
  }
}
