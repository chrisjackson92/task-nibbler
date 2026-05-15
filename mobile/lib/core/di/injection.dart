import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../auth/token_storage.dart';
import '../cache/task_cache.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/gamification/bloc/gamification_cubit.dart';
import '../../features/settings/bloc/settings_cubit.dart';
import '../../features/tasks/bloc/task_list_bloc.dart';
import '../../features/tasks/data/task_repository.dart';
import '../connectivity/connectivity_cubit.dart';

/// Simple manual dependency injection container (BLU-004 §2).
/// All singletons are created here and passed via BlocProvider / Provider.
///
/// Not using GetIt for Sprint 1–2 — constructor injection is sufficient.
class Injection {
  Injection._();

  static late Injection _instance;
  static Injection get instance => _instance;

  late final TokenStorage tokenStorage;
  late final TaskCache taskCache;
  late final AuthRepository authRepository;
  late final TaskRepository taskRepository;
  late final AuthBloc authBloc;
  late final TaskListBloc taskListBloc;
  late final GamificationCubit gamificationCubit;
  late final ConnectivityCubit connectivityCubit;
  late final GlobalKey<NavigatorState> navigatorKey;

  static Future<Injection> initialise() async {
    final inj = Injection._();
    _instance = inj;

    inj.navigatorKey = GlobalKey<NavigatorState>();

    // Storage
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    inj.tokenStorage = const TokenStorage(secureStorage);
    inj.taskCache = const TaskCache();

    // Dio — onTokenExpired wired after authBloc is created.
    // We use a late callback pattern to break the circular dependency.
    void Function()? onTokenExpiredCallback;

    final dio = createDioClient(
      tokenStorage: inj.tokenStorage,
      onTokenExpired: () => onTokenExpiredCallback?.call(),
    );

    // Repositories
    inj.authRepository = AuthRepository(
      dio: dio,
      tokenStorage: inj.tokenStorage,
    );
    inj.taskRepository = TaskRepository(
      dio: dio,
      taskCache: inj.taskCache,
      tokenStorage: inj.tokenStorage,
    );

    // BLoCs / Cubits
    inj.authBloc = AuthBloc(
      authRepository: inj.authRepository,
      taskCache: inj.taskCache,
    );

    // Wire the callback now that authBloc exists.
    onTokenExpiredCallback = () => inj.authBloc.add(const AuthTokenExpired());

    inj.gamificationCubit = GamificationCubit();
    inj.connectivityCubit = ConnectivityCubit();

    // TaskListBloc — created as singleton so screens that push/pop share state.
    inj.taskListBloc = TaskListBloc(
      taskRepository: inj.taskRepository,
      taskCache: inj.taskCache,
      connectivityCubit: inj.connectivityCubit,
      gamificationCubit: inj.gamificationCubit,
    );

    return inj;
  }

  SettingsCubit createSettingsCubit() =>
      SettingsCubit(authBloc: authBloc);

  void dispose() {
    authBloc.close();
    taskListBloc.close();
    gamificationCubit.close();
    connectivityCubit.close();
  }
}
