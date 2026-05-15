import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only request/response logger. Masks the Authorization header
/// so access tokens are never logged (GOV-011 §4.3).
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final sanitised = Map<String, dynamic>.from(options.headers)
        ..remove('Authorization'); // never log tokens
      dev.log(
        '→ ${options.method} ${options.uri}  headers: $sanitised',
        name: 'HTTP',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      dev.log(
        '← ${response.statusCode} ${response.requestOptions.uri}',
        name: 'HTTP',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      dev.log(
        '✗ ${err.response?.statusCode} ${err.requestOptions.uri}: ${err.message}',
        name: 'HTTP',
        error: err,
      );
    }
    handler.next(err);
  }
}
