/// Helper to unwrap the backend's `{success, data, message, errors, pagination}`
/// envelope while staying tolerant of legacy responses that aren't wrapped.
///
/// Returns `data` if the envelope is present, otherwise the raw body.
class ApiEnvelope {
  final bool success;
  final dynamic data;
  final String message;
  final List<dynamic> errors;
  final Map<String, dynamic>? pagination;

  ApiEnvelope({
    required this.success,
    required this.data,
    this.message = '',
    this.errors = const [],
    this.pagination,
  });

  /// Smart-unwrap: returns `body['data']` if the envelope is detected,
  /// else returns the raw body. Lists & primitives pass through unchanged.
  static dynamic unwrap(dynamic body) {
    if (body is Map<String, dynamic> && body.containsKey('success')) {
      // Envelope detected.
      if (body['success'] == false) {
        throw ApiException(
          message: body['message']?.toString() ?? 'Request failed',
          errors: (body['errors'] as List?) ?? const [],
        );
      }
      // List endpoint with pagination — return the list directly, the caller
      // can read body['pagination'] separately if needed.
      return body['data'] ?? body;
    }
    return body;
  }

  static List<T> unwrapList<T>(dynamic body, T Function(dynamic) mapper) {
    final unwrapped = unwrap(body);
    if (unwrapped is List) return unwrapped.map(mapper).toList();
    // Legacy DRF `{results: [...]}`
    if (unwrapped is Map && unwrapped['results'] is List) {
      return (unwrapped['results'] as List).map(mapper).toList();
    }
    return const [];
  }

  static Map<String, dynamic>? paginationOf(dynamic body) {
    if (body is Map<String, dynamic>) {
      final p = body['pagination'];
      if (p is Map<String, dynamic>) return p;
    }
    return null;
  }
}

class ApiException implements Exception {
  final String message;
  final List<dynamic> errors;
  final int? statusCode;

  ApiException({required this.message, this.errors = const [], this.statusCode});

  String get fieldErrorsSummary {
    if (errors.isEmpty) return '';
    return errors
        .whereType<Map>()
        .map((e) => '${e['field'] ?? '_'}: ${e['message'] ?? ''}')
        .join('\n');
  }

  @override
  String toString() => 'ApiException: $message';
}
