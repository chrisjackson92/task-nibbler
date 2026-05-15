import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/features/auth/bloc/auth_bloc.dart';
import 'package:task_nibbles/features/auth/bloc/auth_state.dart';
import 'package:task_nibbles/features/auth/data/auth_repository.dart';
import 'package:task_nibbles/core/api/models/auth_models.dart';
import 'package:task_nibbles/core/cache/task_cache.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements AuthRepository {}

class MockTaskCache extends Mock implements TaskCache {}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeDioException extends Fake implements DioException {
  FakeDioException(this._response);
  final Response<dynamic> _response;
  @override
  Response<dynamic>? get response => _response;
}

// ── Test data ─────────────────────────────────────────────────────────────────

final _testUser = AuthUser(
  id: 'user-123',
  email: 'test@example.com',
  timezone: 'UTC',
  createdAt: DateTime(2026, 5, 15),
);

final _testAuthResponse = AuthResponse(
  user: _testUser,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

// ── Fakes for registerFallbackValue ─────────────────────────────────────────

class FakeLoginRequest extends Fake implements LoginRequest {}
class FakeRegisterRequest extends Fake implements RegisterRequest {}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockTaskCache mockTaskCache;

  setUpAll(() {
    registerFallbackValue(FakeLoginRequest());
    registerFallbackValue(FakeRegisterRequest());
  });

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockTaskCache = MockTaskCache();

    // Default stubs
    when(() => mockTaskCache.clear()).thenAnswer((_) async {});
  });

  AuthBloc buildBloc() => AuthBloc(
        authRepository: mockAuthRepository,
        taskCache: mockTaskCache,
      );

  group('AuthBloc — Login', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when login succeeds',
      build: buildBloc,
      setUp: () {
        when(() => mockAuthRepository.login(any())).thenAnswer(
          (_) async => _testAuthResponse,
        );
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'test@example.com',
          password: 'Password1',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (s) => s.user.email,
          'user.email',
          'test@example.com',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when login fails with 401',
      build: buildBloc,
      setUp: () {
        when(() => mockAuthRepository.login(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/auth/login'),
            response: Response(
              requestOptions: RequestOptions(path: '/auth/login'),
              statusCode: 401,
              data: {
                'error': {
                  'code': 'UNAUTHORIZED',
                  'message': 'Invalid credentials',
                  'request_id': 'req-123',
                },
              },
            ),
          ),
        );
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'wrong@example.com',
          password: 'wrongpass',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having(
          (s) => s.message,
          'message',
          'Invalid email or password.',
        ),
      ],
    );
  });

  group('AuthBloc — Register', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when register succeeds',
      build: buildBloc,
      setUp: () {
        when(() => mockAuthRepository.register(any())).thenAnswer(
          (_) async => _testAuthResponse,
        );
      },
      act: (bloc) => bloc.add(
        const AuthRegisterRequested(
          email: 'new@example.com',
          password: 'NewPass1',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits AuthError with EMAIL_ALREADY_EXISTS message',
      build: buildBloc,
      setUp: () {
        when(() => mockAuthRepository.register(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/auth/register'),
            response: Response(
              requestOptions: RequestOptions(path: '/auth/register'),
              statusCode: 409,
              data: {
                'error': {
                  'code': 'EMAIL_ALREADY_EXISTS',
                  'message': 'Email exists',
                  'request_id': 'req-456',
                },
              },
            ),
          ),
        );
      },
      act: (bloc) => bloc.add(
        const AuthRegisterRequested(
          email: 'existing@example.com',
          password: 'Pass1234',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having(
          (s) => s.message,
          'message',
          'An account with that email already exists. Try logging in.',
        ),
      ],
    );
  });

  group('AuthBloc — Logout', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] and clears cache on logout',
      build: buildBloc,
      seed: () => AuthAuthenticated(user: _testUser),
      setUp: () {
        when(() => mockAuthRepository.logout()).thenAnswer((_) async {});
      },
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
      verify: (_) {
        verify(() => mockTaskCache.clear()).called(1);
      },
    );
  });

  group('AuthBloc — Token Expired', () {
    blocTest<AuthBloc, AuthState>(
      'emits AuthUnauthenticated and clears cache when AuthTokenExpired fired',
      build: buildBloc,
      seed: () => AuthAuthenticated(user: _testUser),
      act: (bloc) => bloc.add(const AuthTokenExpired()),
      expect: () => [isA<AuthUnauthenticated>()],
      verify: (_) {
        verify(() => mockTaskCache.clear()).called(1);
      },
    );
  });

  group('AuthBloc — Delete Account', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] and clears cache on delete',
      build: buildBloc,
      seed: () => AuthAuthenticated(user: _testUser),
      setUp: () {
        when(() => mockAuthRepository.deleteAccount())
            .thenAnswer((_) async {});
      },
      act: (bloc) => bloc.add(const AuthDeleteAccountRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
      verify: (_) {
        verify(() => mockTaskCache.clear()).called(1);
      },
    );
  });
}
