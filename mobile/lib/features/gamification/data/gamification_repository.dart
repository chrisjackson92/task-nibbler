import 'package:dio/dio.dart';

import '../../../core/api/models/gamification_models.dart';

/// Wraps the two gamification API routes (CON-002 §5):
///   GET /api/v1/gamification/state
///   GET /api/v1/gamification/badges
class GamificationRepository {
  const GamificationRepository({required this.dio});

  final Dio dio;

  /// GET /gamification/state — fetches real-time streak + tree health.
  Future<GamificationStateData> getState() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/v1/gamification/state',
      );
      return GamificationStateData.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /gamification/badges — returns all 14 badges with earned status.
  Future<List<BadgeData>> getBadges() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/v1/gamification/badges',
      );
      final data = response.data!['data'] as List<dynamic>;
      return data
          .map((e) => BadgeData.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Exception _mapError(DioException e) {
    return GamificationRepositoryException(
      e.message ?? 'Gamification request failed.',
    );
  }
}

class GamificationRepositoryException implements Exception {
  const GamificationRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
