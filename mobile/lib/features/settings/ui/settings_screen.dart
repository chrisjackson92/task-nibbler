import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../bloc/settings_cubit.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';

/// Settings screen — logout and delete account (M-010).
/// Delete requires confirmation dialog before the action is dispatched.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account, all tasks, and all attachments. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<SettingsCubit>().deleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          final isAuthenticated = authState is AuthAuthenticated;
          final user = isAuthenticated ? authState.user : null;

          return ListView(
            children: [
              // ── Account info ───────────────────────────────────────────────
              if (user != null)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      user.email.isNotEmpty
                          ? user.email[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    user.email,
                    style: theme.textTheme.bodyLarge,
                  ),
                  subtitle: Text('Timezone: ${user.timezone}'),
                  trailing: IconButton(
                    key: const Key('settings_edit_profile_button'),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit profile',
                    onPressed: () => context.push(AppRoutes.editProfile),
                  ),
                ),

              const Divider(),

              // ── Logout ─────────────────────────────────────────────────────
              ListTile(
                key: const Key('settings_logout_button'),
                leading: const Icon(Icons.logout),
                title: const Text('Log Out'),
                onTap: isAuthenticated
                    ? () => context.read<SettingsCubit>().logout()
                    : null,
              ),

              const Divider(),

              // ── Danger zone ────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Danger Zone',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ListTile(
                key: const Key('settings_delete_account_button'),
                leading: Icon(Icons.delete_forever,
                    color: theme.colorScheme.error),
                title: Text(
                  'Delete Account',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text('Permanently deletes all data'),
                onTap: isAuthenticated
                    ? () => _confirmDeleteAccount(context)
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
