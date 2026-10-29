bool isSupabaseAdminAnalyticsRequest(String path, {required String method}) {
  final uri = Uri.tryParse(path);
  final normalizedPath = (uri?.path ?? path).replaceAll(RegExp(r'^/+|/+$'), '');
  return method.toUpperCase() == 'GET' && normalizedPath == 'analytics';
}

String supabaseAdminAnalyticsPeriod(String path) {
  final period = Uri.tryParse(path)?.queryParameters['period']?.toLowerCase();
  return switch (period) {
    'daily' || 'weekly' || 'monthly' => period!,
    _ => 'yearly',
  };
}
