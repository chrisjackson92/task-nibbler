import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/auth/ui/register_screen.dart';
import '../../features/auth/ui/forgot_password_screen.dart';
import '../../features/auth/ui/reset_password_screen.dart';
import '../../features/tasks/ui/task_list_screen.dart';
import '../../features/gamification/ui/gamification_detail_screen.dart';
import '../../features/settings/ui/settings_screen.dart';

/// Route path constants — never use bare string paths in feature code.
abstract final class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const tasks = '/tasks';
  static const settings = '/settings';
  static const gamification = '/gamification';
}

/// All auth page paths — used by the redirect guard.
bool _isAuthPath(String location) =>
    location.startsWith(AppRoutes.login) ||
    location.startsWith(AppRoutes.register) ||
    location.startsWith(AppRoutes.forgotPassword) ||
    location.startsWith(AppRoutes.resetPassword);

/// go_router configuration with auth guard and deep link support.
/// Single source of truth for all routes (GOV-011 §3.1, BLU-004 §6).
GoRouter createRouter(GlobalKey<NavigatorState> navigatorKey) => GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: AppRoutes.login,
      redirect: (BuildContext context, GoRouterState state) {
        final authState = context.read<AuthBloc>().state;
        final isAuth = authState is AuthAuthenticated;
        final onAuthPage = _isAuthPath(state.matchedLocation);

        if (!isAuth && !onAuthPage) return AppRoutes.login;
        if (isAuth && onAuthPage) return AppRoutes.tasks;
        return null;
      },
      routes: [
        // ── Auth ────────────────────────────────────────────────────────────
        GoRoute(
          path: AppRoutes.login,
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (_, __) => const RegisterScreen(),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (_, __) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          // Deep linked from reset-password email:
          // tasknibbles://reset-password?token=<raw>
          path: AppRoutes.resetPassword,
          builder: (_, state) {
            final token = state.uri.queryParameters['token'] ?? '';
            return ResetPasswordScreen(token: token);
          },
        ),

        // ── App ─────────────────────────────────────────────────────────────
        GoRoute(
          path: AppRoutes.tasks,
          builder: (_, __) => const TaskListScreen(),
        ),
        GoRoute(
          path: AppRoutes.gamification,
          builder: (_, __) => const GamificationDetailScreen(),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const SettingsScreen(),
        ),
      ],
      errorBuilder: (_, state) => Scaffold(
        body: Center(child: Text('Route not found: ${state.uri}')),
      ),
    );
