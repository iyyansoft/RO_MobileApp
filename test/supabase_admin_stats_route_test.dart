import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_stats_route.dart';

void main() {
  test('routes only dashboard-stats GET requests through the opt-in path', () {
    expect(
      isSupabaseAdminStatsRequest('dashboard-stats', method: 'GET'),
      isTrue,
    );
    expect(
      isSupabaseAdminStatsRequest('/dashboard-stats/', method: 'get'),
      isTrue,
    );
    expect(
      isSupabaseAdminStatsRequest('analytics?period=monthly', method: 'GET'),
      isFalse,
    );
    expect(
      isSupabaseAdminStatsRequest('dashboard-stats', method: 'POST'),
      isFalse,
    );
  });
}
