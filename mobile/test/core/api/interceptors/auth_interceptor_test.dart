import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/interceptors/auth_interceptor.dart';
import 'package:task_nibbles/core/auth/token_storage.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTokenStorage extends Mock implements TokenStorage {}
class MockDio extends Mock implements Dio {}

void main() {
  late MockTokenStorage mockTokenStorage;
  late MockDio mockDio;
  late bool tokenExpiredCalled;
  late AuthInterceptor interceptor;

  setUp(() {
    mockTokenStorage = MockTokenStorage();
    mockDio = MockDio();
    tokenExpiredCalled = false;

    interceptor = AuthInterceptor(
      dio: mockDio,
      tokenStorage: mockTokenStorage,
      onTokenExpired: () => tokenExpiredCalled = true,
    );
  });

  group('AuthInterceptor — onRequest', () {
    test('injects Authorization header when access token is present', () async {
      when(() => mockTokenStorage.getAccessToken())
          .thenAnswer((_) async => 'my-access-token');

      final options = RequestOptions(path: '/api/v1/tasks');
      var nextCalled = false;

      await interceptor.onRequest(
        options,
        _MockRequestHandler(onNext: (opts) {
          nextCalled = true;
          expect(opts.headers['Authorization'], 'Bearer my-access-token');
        }),
      );

      expect(nextCalled, isTrue);
    });

    test('does not inject Authorization header when no token present', () async {
      when(() => mockTokenStorage.getAccessToken()).thenAnswer((_) async => null);

      final options = RequestOptions(path: '/api/v1/tasks');

      await interceptor.onRequest(
        options,
        _MockRequestHandler(onNext: (opts) {
          expect(opts.headers.containsKey('Authorization'), isFalse);
        }),
      );
    });
  });

  group('AuthInterceptor — 401 handling', () {
    test('fires onTokenExpired when refresh token is null', () async {
      when(() => mockTokenStorage.getRefreshToken())
          .thenAnswer((_) async => null);
      when(() => mockTokenStorage.clearTokens()).thenAnswer((_) async {});

      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v1/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/tasks'),
          statusCode: 401,
        ),
      );

      await interceptor.onError(err, _MockErrorHandler());

      expect(tokenExpiredCalled, isTrue);
    });

    test('fires onTokenExpired when refresh call fails', () async {
      when(() => mockTokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'old-refresh');
      when(() => mockTokenStorage.clearTokens()).thenAnswer((_) async {});
      when(
        () => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
            statusCode: 401,
          ),
        ),
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v1/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/tasks'),
          statusCode: 401,
        ),
      );

      await interceptor.onError(err, _MockErrorHandler());

      expect(tokenExpiredCalled, isTrue);
    });
  });

  group('AuthInterceptor — non-401 passthrough', () {
    test('passes through non-401 errors unchanged', () async {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v1/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/tasks'),
          statusCode: 500,
        ),
      );

      bool nextCalled = false;
      await interceptor.onError(
        err,
        _MockErrorHandler(onNext: (_) => nextCalled = true),
      );

      expect(nextCalled, isTrue);
      expect(tokenExpiredCalled, isFalse);
    });
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

class _MockRequestHandler extends RequestInterceptorHandler {
  _MockRequestHandler({required this.onNext});
  final void Function(RequestOptions) onNext;

  @override
  void next(RequestOptions requestOptions) => onNext(requestOptions);
}

class _MockErrorHandler extends ErrorInterceptorHandler {
  _MockErrorHandler({this.onNext});
  final void Function(DioException)? onNext;

  @override
  void next(DioException err) => onNext?.call(err);

  @override
  void resolve(Response response) {}
}
