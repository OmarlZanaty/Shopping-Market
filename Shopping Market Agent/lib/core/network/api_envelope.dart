/// Helper to unwrap the backend's `{success, data, message, errors, pagination}`
/// envelope. Tolerant of legacy `{results: [...]}` and raw shapes.
class ApiEnvelope {
  static dynamic unwrap(dynamic body) {
    if (body is Map<String, dynamic> && body.containsKey('success')) {
      if (body['success'] == false) {
        throw ApiException(
          message: body['message']?.toString() ?? 'Request failed',
          errors: (body['errors'] as List?) ?? const [],
        );
      }
      return body['data'] ?? body;
    }
    return body;
  }

  static List<T> unwrapList<T>(dynamic body, T Function(dynamic) mapper) {
    final u = unwrap(body);
    if (u is List) return u.map(mapper).toList();
    if (u is Map && u['results'] is List) {
      return (u['results'] as List).map(mapper).toList();
    }
    return const [];
  }
}

class ApiException implements Exception {
  final String message;
  final List<dynamic> errors;
  final int? statusCode;
  ApiException({required this.message, this.errors = const [], this.statusCode});
  @override
  String toString() => message;
}
