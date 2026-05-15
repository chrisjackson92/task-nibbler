import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/features/auth/bloc/auth_bloc.dart';
import 'package:task_nibbles/features/auth/bloc/auth_state.dart';
import 'package:task_nibbles/features/settings/bloc/settings_cubit.dart';
import 'package:task_nibbles/features/settings/ui/settings_screen.dart';
import 'package:task_nibbles/core/api/models/auth_models.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}
class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

final _testUser = AuthUser(
  id: 'user-123',
  email: 'test@example.com',
  timezone: 'UTC',
  createdAt: DateTime(2026, 5, 15),
);

void main() {
  late MockAuthBloc mockAuthBloc;
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockAuthBloc = MockAuthBloc();
    mockSettingsCubit = MockSettingsCubit();
    when(() => mockSettingsCubit.state).thenReturn(const SettingsIdle());
  });

  Widget buildSubject({AuthState? authState}) {
    final resolvedState = authState ?? const AuthInitial();
    when(() => mockAuthBloc.state).thenReturn(resolvedState);
    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        ],
        child: const SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen widget tests', () {
    testWidgets('logout button is visible when user is authenticated',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(
          authState: AuthAuthenticated(user: _testUser),
        ),
      );

      expect(find.byKey(const Key('settings_logout_button')), findsOneWidget);
    });

    testWidgets('delete account button is visible when authenticated',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(
          authState: AuthAuthenticated(user: _testUser),
        ),
      );

      expect(
        find.byKey(const Key('settings_delete_account_button')),
        findsOneWidget,
      );
    });

    testWidgets('shows user email in account section when authenticated',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(
          authState: AuthAuthenticated(user: _testUser),
        ),
      );

      expect(find.text('test@example.com'), findsOneWidget);
    });
  });
}
