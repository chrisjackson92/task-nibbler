import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../auth/token_storage.dart';
import '../cache/task_cache.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/gamification/bloc/gamification_cubit.dart';
import '../../features/settings/bloc/settings_cubit.dart';
import '../connectivity/connectivity_cubit.dart';

/// Simple manual dependency injection container (BLU-004 §2).
/// All singletons are created here and passed via BlocProvider / Provider.
///
/// Not using GetIt for Sprint 1 — constructor injection is sufficient.
class Injection {
  Injection._();

  static late Injection _instance;
  static Injection get instance => _instance;

  late final TokenStorage tokenStorage;
  late final Dio dio;
  late final AuthRepository authRepository;
  late final TaskCache taskCache;
  late final AuthBloc authBloc;
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

    inj.dio = createDioClient(
      tokenStorage: inj.tokenStorage,
      onTokenExpired: () => onTokenExpiredCallback?.call(),
    );

    // Repository
    inj.authRepository = AuthRepository(
      dio: inj.dio,
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

    return inj;
  }

  SettingsCubit createSettingsCubit() =>
      SettingsCubit(authBloc: authBloc);

  void dispose() {
    authBloc.close();
    gamificationCubit.close();
    connectivityCubit.close();
  }
}
