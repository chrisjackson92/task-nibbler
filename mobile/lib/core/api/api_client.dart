import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';

/// Base URL injected at build time via --dart-define (AGT-002-MB §5.2).
const _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Creates and configures the shared [Dio] instance.
///
/// [onTokenExpired] is called by [AuthInterceptor] when a silent refresh fails.
/// Wire this to `AuthBloc.add(AuthTokenExpired())` in [Injection].
Dio createDioClient({
  required TokenStorage tokenStorage,
  required void Function() onTokenExpired,
  String baseUrl = _kApiBaseUrl,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final authInterceptor = AuthInterceptor(
    dio: dio,
    tokenStorage: tokenStorage,
    onTokenExpired: onTokenExpired,
  );

  dio.interceptors.addAll([
    authInterceptor,
    if (kDebugMode) LoggingInterceptor(),
  ]);

  return dio;
}
