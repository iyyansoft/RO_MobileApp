bool isSupabaseAdminDealersRequest(String path, {required String method}) {
  final normalizedPath = path
      .split('?')
      .first
      .replaceAll(RegExp(r'^/+|/+$'), '');
  if (method.toUpperCase() != 'GET' || normalizedPath != 'dealers') {
    return false;
  }
  return true;
}
