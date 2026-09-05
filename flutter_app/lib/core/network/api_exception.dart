class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code = 'REQUEST_FAILED',
    this.statusCode,
    this.retryAt,
    this.issues = const [],
    this.cause,
  });

  final String code;
  final String message;
  final int? statusCode;

  /// Earliest retry time from the server's Retry-After response header.
  final DateTime? retryAt;
  final List<dynamic> issues;
  final Object? cause;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
