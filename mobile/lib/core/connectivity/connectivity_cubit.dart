import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Online/offline connectivity status.
enum ConnectivityStatus { connected, disconnected }

/// Emits [ConnectivityStatus.disconnected] when the device loses internet
/// and [ConnectivityStatus.connected] when it reconnects (BLU-004 §9).
class ConnectivityCubit extends Cubit<ConnectivityStatus> {
  ConnectivityCubit() : super(ConnectivityStatus.connected) {
    _subscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
  }

  late final StreamSubscription<List<ConnectivityResult>> _subscription;

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOffline = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    emit(
      isOffline ? ConnectivityStatus.disconnected : ConnectivityStatus.connected,
    );
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
