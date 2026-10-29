bool isSupabaseAdminStatsRequest(String path, {required String method}) {
  final normalizedPath = path
      .split('?')
      .first
      .replaceAll(RegExp(r'^/+|/+$'), '');
  return method.toUpperCase() == 'GET' && normalizedPath == 'dashboard-stats';
}
