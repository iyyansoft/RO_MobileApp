import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_analytics_route.dart';

void main() {
  test('routes only the analytics GET and preserves a safe period', () {
    expect(
      isSupabaseAdminAnalyticsRequest(
        'analytics?period=monthly',
        method: 'GET',
      ),
      isTrue,
    );
    expect(
      isSupabaseAdminAnalyticsRequest('/analytics/', method: 'get'),
      isTrue,
    );
    expect(isSupabaseAdminAnalyticsRequest('orders', method: 'GET'), isFalse);
    expect(
      isSupabaseAdminAnalyticsRequest('analytics', method: 'POST'),
      isFalse,
    );
    expect(supabaseAdminAnalyticsPeriod('analytics?period=weekly'), 'weekly');
    expect(supabaseAdminAnalyticsPeriod('analytics?period=monthly'), 'monthly');
    expect(supabaseAdminAnalyticsPeriod('analytics?period=daily'), 'daily');
    expect(supabaseAdminAnalyticsPeriod('analytics?period=unknown'), 'yearly');
    expect(supabaseAdminAnalyticsPeriod('analytics'), 'yearly');
  });
}
