import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/cache/task_cache.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/gamification/bloc/gamification_cubit.dart';
import 'features/settings/bloc/settings_cubit.dart';
import 'core/connectivity/connectivity_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Hive init (M-011) ─────────────────────────────────────────────────────
  await Hive.initFlutter();
  await Hive.openBox<dynamic>(kTaskBoxName);

  // ── DI ────────────────────────────────────────────────────────────────────
  final injection = await Injection.initialise();

  // ── Session restore (fires before first frame is painted) ─────────────────
  // Reads stored refresh token and silently re-authenticates the user so they
  // don't have to log in every time they open the app.
  injection.authBloc.add(const AuthRestoreSessionRequested());

  runApp(TaskNibblesApp(injection: injection));
}

class TaskNibblesApp extends StatelessWidget {
  const TaskNibblesApp({super.key, required this.injection});

  final Injection injection;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: injection.authBloc),
          BlocProvider<GamificationCubit>.value(
              value: injection.gamificationCubit),
          BlocProvider<ConnectivityCubit>.value(
              value: injection.connectivityCubit),
          // SettingsCubit is created per-screen (not a singleton) since it
          // only delegates to AuthBloc which IS a singleton.
          BlocProvider<SettingsCubit>(
            create: (_) => injection.createSettingsCubit(),
          ),
        ],
        child: Builder(
          builder: (context) {
            final router = createRouter(
              authBloc: injection.authBloc,
              navigatorKey: injection.navigatorKey,
            );
            return MaterialApp.router(
              title: 'Task Nibbles',
              theme: appTheme,
              darkTheme: darkTheme,
              themeMode: ThemeMode.system,
              routerConfig: router,
              debugShowCheckedModeBanner: false,
            );
          },
        ),
      );
}
