class SupabaseAdminOrderStatusRequest {
  const SupabaseAdminOrderStatusRequest({
    required this.orderId,
    required this.status,
  });

  final String orderId;
  final String status;

  Map<String, dynamic> toJson() => {'orderId': orderId, 'status': status};
}

SupabaseAdminOrderStatusRequest? mapSupabaseAdminOrderStatusRequest(
  String path, {
  required String method,
  dynamic data,
}) {
  if (method.toUpperCase() != 'PUT') return null;
  final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
  if (segments.length != 3 ||
      segments[0] != 'orders' ||
      segments[2] != 'status') {
    return null;
  }
  final orderId = segments[1].trim();
  final status =
      '${data is Map ? data['status'] ?? 'Processing' : 'Processing'}'.trim();
  return SupabaseAdminOrderStatusRequest(orderId: orderId, status: status);
}
