import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../connectivity/connectivity_cubit.dart';
import '../theme/app_colors.dart';

/// Shown at the top of every screen when [ConnectivityStatus.disconnected].
/// Disappears automatically when the device reconnects.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityCubit, ConnectivityStatus>(
      buildWhen: (prev, curr) => prev != curr,
      builder: (context, status) => Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: status == ConnectivityStatus.disconnected ? 36 : 0,
            color: AppColors.offlineBanner,
            child: status == ConnectivityStatus.disconnected
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'You\'re offline — showing cached data',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
