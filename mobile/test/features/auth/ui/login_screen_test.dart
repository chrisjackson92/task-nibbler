import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/features/auth/bloc/auth_bloc.dart';
import 'package:task_nibbles/features/auth/bloc/auth_state.dart';
import 'package:task_nibbles/features/auth/ui/login_screen.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    // AuthEvent is sealed; use a concrete subclass as fallback for any() matcher.
    registerFallbackValue(const AuthTokenExpired());
  });

  setUp(() {
    mockAuthBloc = MockAuthBloc();
    when(() => mockAuthBloc.state).thenReturn(const AuthInitial());
  });

  Widget buildSubject() => MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockAuthBloc,
          child: const LoginScreen(),
        ),
      );

  group('LoginScreen widget tests', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    });

    testWidgets('renders Log In submit button', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
    });

    testWidgets('dispatches event to AuthBloc on valid submit', (tester) async {
      await tester.pumpWidget(buildSubject());

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'Password1',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      // Verify AuthBloc received exactly one add() call (AuthLoginRequested).
      verify(() => mockAuthBloc.add(any())).called(1);
    });

    testWidgets('shows validation error when email is empty', (tester) async {
      await tester.pumpWidget(buildSubject());

      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });
  });
}
