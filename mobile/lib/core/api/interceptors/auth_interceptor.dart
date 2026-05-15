import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../auth/token_storage.dart';
import '../models/auth_models.dart';

/// Injects the Bearer token on every request and performs silent token refresh
/// on 401 responses. Concurrent 401 responses share a single refresh call
/// via the [_isRefreshing] lock and [_queue].
///
/// IMPORTANT: This interceptor is the ONLY place allowed to read tokens from
/// [TokenStorage]. Feature code must never access tokens directly.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.tokenStorage,
    required this.onTokenExpired,
  });

  final Dio dio;
  final TokenStorage tokenStorage;

  /// Called when silent refresh fails — signals [AuthBloc] to emit Unauthenticated.
  final void Function() onTokenExpired;

  bool _isRefreshing = false;
  final List<(RequestOptions, ErrorInterceptorHandler)> _queue = [];

  // ── Request ────────────────────────────────────────────────────────────────

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Avoid refreshing on the refresh endpoint itself (prevents infinite loop).
    if (err.requestOptions.path.contains('/auth/refresh')) {
      return handler.next(err);
    }

    if (_isRefreshing) {
      // Queue this request; it will be retried after refresh completes.
      _queue.add((err.requestOptions, handler));
      return;
    }

    _isRefreshing = true;

    final refreshed = await _tryRefreshToken();

    _isRefreshing = false;

    if (refreshed) {
      // Retry all queued requests.
      for (final (opts, h) in _queue) {
        final newToken = await tokenStorage.getAccessToken();
        opts.headers['Authorization'] = 'Bearer $newToken';
        try {
          final response = await dio.fetch(opts);
          h.resolve(response);
        } on DioException catch (e) {
          h.next(e);
        }
      }
      _queue.clear();

      // Retry the original request.
      final newToken = await tokenStorage.getAccessToken();
      err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }

    // Refresh failed — clear queue and signal auth failure.
    for (final (_, h) in _queue) {
      h.next(err);
    }
    _queue.clear();

    onTokenExpired();
    handler.next(err);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<bool> _tryRefreshToken() async {
    try {
      final refreshToken = await tokenStorage.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: RefreshRequest(refreshToken: refreshToken).toJson(),
      );

      final parsed = RefreshResponse.fromJson(response.data!);
      await tokenStorage.saveTokens(
        accessToken: parsed.accessToken,
        refreshToken: parsed.refreshToken,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        dev.log('AuthInterceptor: token refresh failed → $e',
            name: 'AuthInterceptor');
      }
      await tokenStorage.clearTokens();
      return false;
    }
  }
}
