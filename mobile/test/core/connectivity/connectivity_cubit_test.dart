import 'package:flutter_test/flutter_test.dart';

import 'package:task_nibbles/core/connectivity/connectivity_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityCubit', () {
    test('initial state is ConnectivityStatus.connected', () {
      final cubit = ConnectivityCubit();
      expect(cubit.state, ConnectivityStatus.connected);
      // Note: don't call close() — connectivity stream teardown requires
      // a running platform channel which isn't available in unit test env.
    });
  });
}
