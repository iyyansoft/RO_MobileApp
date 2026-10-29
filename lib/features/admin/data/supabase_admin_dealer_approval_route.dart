/// Maps the existing Admin Web dealer approval endpoint to a separately
/// gated, server-authorized Supabase Edge Function.
class SupabaseAdminDealerApprovalRequest {
  const SupabaseAdminDealerApprovalRequest({
    required this.identifier,
    required this.status,
  });

  final String identifier;
  final String status;

  Map<String, dynamic> toJson() => {'identifier': identifier, 'status': status};
}

SupabaseAdminDealerApprovalRequest? mapSupabaseAdminDealerApprovalRequest(
  String path, {
  required String method,
  dynamic data,
}) {
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.decodeComponent)
      .toList(growable: false);
  if (segments.length != 1 ||
      segments.single != 'set-status' ||
      method.toUpperCase() != 'POST' ||
      data is! Map) {
    return null;
  }
  final identifier = '${data['identifier'] ?? data['email'] ?? ''}'.trim();
  final status = '${data['status'] ?? ''}'.trim().toLowerCase();
  if (identifier.isEmpty ||
      identifier.length > 320 ||
      !const {'approved', 'pending', 'rejected'}.contains(status)) {
    return null;
  }
  return SupabaseAdminDealerApprovalRequest(
    identifier: identifier,
    status: status,
  );
}
