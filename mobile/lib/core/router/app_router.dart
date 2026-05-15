import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/ui/forgot_password_screen.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/auth/ui/register_screen.dart';
import '../../features/auth/ui/reset_password_screen.dart';
import '../../features/gamification/ui/gamification_detail_screen.dart';
import '../../features/settings/bloc/settings_cubit.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/tasks/bloc/task_form_cubit.dart';
import '../../features/tasks/bloc/task_list_bloc.dart';
import '../../features/tasks/ui/task_detail_screen.dart';
import '../../features/tasks/ui/task_form_screen.dart';
import '../../features/tasks/ui/task_list_screen.dart';
import '../api/models/task_models.dart';
import '../di/injection.dart';

/// Route name constants — feature code MUST use these, never bare strings.
abstract class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const tasks = '/tasks';
  static const taskCreate = '/tasks/new';
  static const taskDetail = '/tasks/:id';
  static const taskEdit = '/tasks/:id/edit';
  static const settings = '/settings';
  static const gamification = '/gamification';
}

GoRouter createRouter({
  required AuthBloc authBloc,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    debugLogDiagnostics: true,
    initialLocation: AppRoutes.tasks,
    redirect: (context, state) {
      final authState = authBloc.state;
      final isAuthenticated = authState is AuthAuthenticated;
      final isOnAuthPath = _isAuthPath(state.uri.path);

      if (!isAuthenticated && !isOnAuthPath) return AppRoutes.login;
      if (isAuthenticated && isOnAuthPath) return AppRoutes.tasks;
      return null;
    },
    refreshListenable: _BlocListenable(authBloc.stream),
    routes: [
      // ── Auth ────────────────────────────────────────────────────────────────
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
        path: AppRoutes.resetPassword,
        builder: (_, state) =>
            ResetPasswordScreen(token: state.uri.queryParameters['token'] ?? ''),
      ),

      // ── Tasks ────────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.tasks,
        builder: (context, _) => BlocProvider<TaskListBloc>(
          create: (_) => TaskListBloc(
            taskRepository: Injection.instance.taskRepository,
            taskCache: Injection.instance.taskCache,
            connectivityCubit: Injection.instance.connectivityCubit,
            gamificationCubit: Injection.instance.gamificationCubit,
          ),
          child: const TaskListScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.taskCreate,
        builder: (context, _) => BlocProvider<TaskFormCubit>(
          create: (_) => TaskFormCubit(
            taskRepository: Injection.instance.taskRepository,
          ),
          child: BlocProvider.value(
            value: Injection.instance.taskListBloc,
            child: const TaskFormScreen(),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) {
          final task = state.extra as Task?;
          if (task == null) {
            // Fallback: redirect to task list if no task passed.
            return const TaskListScreen();
          }
          return BlocProvider.value(
            value: Injection.instance.taskListBloc,
            child: TaskDetailScreen(task: task),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.taskEdit,
        builder: (context, state) {
          // Support both bare Task (from old push) and _TaskEditExtra (from scope dialog)
          final extra = state.extra;
          final Task? task;
          RecurringEditScope? scope;

          if (extra is Task) {
            task = extra;
          } else if (extra is TaskEditExtra) {
            task = extra.task;
            scope = extra.scope;
          } else {
            task = null;
          }

          if (task == null) return const TaskListScreen();
          return MultiBlocProvider(
            providers: [
              BlocProvider<TaskFormCubit>(
                create: (_) {
                  final cubit = TaskFormCubit(
                    taskRepository: Injection.instance.taskRepository,
                  );
                  if (scope != null) cubit.setScope(scope);
                  return cubit;
                },
              ),
              BlocProvider.value(value: Injection.instance.taskListBloc),
            ],
            child: TaskFormScreen(existingTask: task),
          );
        },
      ),

      // ── Settings ─────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => BlocProvider<SettingsCubit>(
          create: (_) => Injection.instance.createSettingsCubit(),
          child: const SettingsScreen(),
        ),
      ),

      // ── Gamification ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.gamification,
        builder: (_, __) => BlocProvider.value(
          value: Injection.instance.gamificationCubit,
          child: const GamificationDetailScreen(),
        ),
      ),
    ],
  );
}

bool _isAuthPath(String path) =>
    path == AppRoutes.login ||
    path == AppRoutes.register ||
    path == AppRoutes.forgotPassword ||
    path.startsWith(AppRoutes.resetPassword);

// Bridges Stream to Listenable for go_router refresh.
class _BlocListenable extends ChangeNotifier {
  _BlocListenable(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
