import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles notification permission request and persistence (M-054, SPR-010-MB).
///
/// Called by [AuthBloc] after emitting [AuthAuthenticated].
/// Stores the result in Hive `'settings'` box so it is only requested once.
///
/// DO NOT integrate Firebase/FlutterFire. The device token retrieval
/// (APNs/FCM) is out-of-scope for this sprint.
class NotificationPermissionService {
  NotificationPermissionService._();

  static const _boxName = 'settings';
  static const _key = 'notification_permission_granted';

  /// Requests notification permission if it has not been determined yet.
  ///
  /// - Uses `permission_handler`'s [Permission.notification.request()].
  /// - On iOS: wraps `UNUserNotificationCenter`.
  /// - On Android 13+: wraps `POST_NOTIFICATIONS`.
  /// - Denial is silent — no error UI, no repeat prompt.
  /// - Granted status is stored in Hive `'settings'['notification_permission_granted']`.
  static Future<void> requestIfNeeded() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);

      // If already determined, do nothing.
      final alreadyAsked = box.get(_key);
      if (alreadyAsked != null) return;

      final status = await Permission.notification.request();

      // Store result regardless of grant/deny so we only ask once.
      await box.put(_key, status.isGranted);
    } catch (_) {
      // Fail silently — notification permission is non-critical.
    }
  }
}
