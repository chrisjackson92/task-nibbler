/// API error model matching CON-001 §5 error envelope.
class ApiError {
  const ApiError({
    required this.code,
    required this.message,
    required this.requestId,
    this.details,
  });

  final String code;
  final String message;
  final String requestId;
  final Map<String, dynamic>? details;

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final err = json['error'] as Map<String, dynamic>? ?? json;
    return ApiError(
      code: err['code'] as String? ?? 'INTERNAL_ERROR',
      message: err['message'] as String? ?? 'An unexpected error occurred.',
      requestId: err['request_id'] as String? ?? '',
      details: err['details'] as Map<String, dynamic>?,
    );
  }

  /// Returns the first validation message for [field], or null.
  String? fieldError(String field) {
    final list = details?[field];
    if (list is List && list.isNotEmpty) return list.first as String;
    return null;
  }

  @override
  String toString() => 'ApiError($code): $message';
}
