import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/models/auth_models.dart';
import '../../../core/widgets/error_snackbar.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../../auth/data/auth_repository.dart';

/// Full profile editing screen (SPR-009-MB):
/// - Display name
/// - Timezone (searchable IANA picker)
/// - Change password
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _currentPasswordCtrl;
  late final TextEditingController _newPasswordCtrl;
  late final TextEditingController _confirmPasswordCtrl;

  late String _selectedTimezone;
  final _timezoneSearchCtrl = TextEditingController();

  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // A curated list of common IANA timezone identifiers.
  static const List<String> _allTimezones = [
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'America/Honolulu',
    'America/Toronto',
    'America/Vancouver',
    'America/Sao_Paulo',
    'America/Buenos_Aires',
    'America/Mexico_City',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Moscow',
    'Europe/Istanbul',
    'Africa/Cairo',
    'Africa/Nairobi',
    'Africa/Lagos',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Dhaka',
    'Asia/Bangkok',
    'Asia/Singapore',
    'Asia/Shanghai',
    'Asia/Tokyo',
    'Asia/Seoul',
    'Asia/Jakarta',
    'Australia/Sydney',
    'Australia/Melbourne',
    'Pacific/Auckland',
    'Pacific/Honolulu',
  ];

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    AuthUser? user;
    if (authState is AuthAuthenticated) user = authState.user;

    _displayNameCtrl = TextEditingController(text: user?.displayName ?? '');
    _currentPasswordCtrl = TextEditingController();
    _newPasswordCtrl = TextEditingController();
    _confirmPasswordCtrl = TextEditingController();
    _selectedTimezone = user?.timezone ?? 'UTC';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _timezoneSearchCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  List<String> get _filteredTimezones {
    final q = _timezoneSearchCtrl.text.toLowerCase();
    if (q.isEmpty) return _allTimezones;
    return _allTimezones.where((tz) => tz.toLowerCase().contains(q)).toList();
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      final repo = context.read<AuthRepository>();
      final user = await repo.updateProfile(
        displayName: _displayNameCtrl.text.trim().isEmpty
            ? null
            : _displayNameCtrl.text.trim(),
        timezone: _selectedTimezone,
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthProfileUpdated(user: user));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Could not update profile.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    if (_newPasswordCtrl.text != _confirmPasswordCtrl.text) {
      showErrorSnackBar(context, 'New passwords do not match.');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await context.read<AuthRepository>().changePassword(
            currentPassword: _currentPasswordCtrl.text,
            newPassword: _newPasswordCtrl.text,
          );
      if (!mounted) return;
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Could not change password. Check your current password.');
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Profile section ───────────────────────────────────────────────
          Text('Profile', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Form(
            key: _profileFormKey,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('edit_display_name_field'),
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display Name (optional)',
                    prefixIcon: Icon(Icons.person_outline),
                    hintText: 'How others see your name',
                  ),
                ),
                const SizedBox(height: 16),
                // Timezone picker
                Text('Timezone', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _timezoneSearchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Search timezones…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 180,
                  child: Card(
                    clipBehavior: Clip.hardEdge,
                    child: ListView.builder(
                      itemCount: _filteredTimezones.length,
                      itemBuilder: (_, i) {
                        final tz = _filteredTimezones[i];
                        final selected = tz == _selectedTimezone;
                        return ListTile(
                          dense: true,
                          title: Text(tz,
                              style: TextStyle(
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                color: selected ? theme.colorScheme.primary : null,
                              )),
                          trailing: selected
                              ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                              : null,
                          onTap: () => setState(() => _selectedTimezone = tz),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('edit_profile_save_button'),
            onPressed: _savingProfile ? null : _saveProfile,
            icon: _savingProfile
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Save Profile'),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ── Change password section ────────────────────────────────────────
          Text('Change Password', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Form(
            key: _passwordFormKey,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('edit_current_password_field'),
                  controller: _currentPasswordCtrl,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: _toggleVisibility(
                        _obscureCurrent, (v) => setState(() => _obscureCurrent = v)),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('edit_new_password_field'),
                  controller: _newPasswordCtrl,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: _toggleVisibility(
                        _obscureNew, (v) => setState(() => _obscureNew = v)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'Minimum 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('edit_confirm_password_field'),
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: _toggleVisibility(
                        _obscureConfirm, (v) => setState(() => _obscureConfirm = v)),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('edit_change_password_button'),
            onPressed: _savingPassword ? null : _changePassword,
            icon: _savingPassword
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_rounded),
            label: const Text('Change Password'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _toggleVisibility(bool obscure, ValueChanged<bool> onToggle) {
    return IconButton(
      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => onToggle(!obscure),
    );
  }
}
