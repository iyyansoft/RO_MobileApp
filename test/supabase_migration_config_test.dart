import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_config.dart';

void main() {
  test('Supabase cutover remains opt-in until dashboard setup is complete', () {
    expect(SupabaseConfig.authEnabled, isFalse);
    expect(SupabaseConfig.catalogEnabled, isFalse);
    expect(SupabaseConfig.dealerDataEnabled, isFalse);
    expect(SupabaseConfig.checkoutEnabled, isFalse);
    expect(SupabaseConfig.adminCatalogEnabled, isFalse);
    expect(SupabaseConfig.adminBulkImportEnabled, isFalse);
    expect(SupabaseConfig.adminDealerApprovalEnabled, isFalse);
    expect(SupabaseConfig.adminDealersEnabled, isFalse);
    expect(SupabaseConfig.adminStatsEnabled, isFalse);
    expect(SupabaseConfig.adminOrdersEnabled, isFalse);
    expect(SupabaseConfig.adminAnalyticsEnabled, isFalse);
    expect(SupabaseConfig.adminOrderStatusEnabled, isFalse);
    expect(SupabaseConfig.adminShopEnquiriesEnabled, isFalse);
    expect(SupabaseConfig.adminShopNotificationsEnabled, isFalse);
    expect(SupabaseConfig.adminShopEmployeesEnabled, isFalse);
    expect(SupabaseConfig.adminSupabaseEnabled, isFalse);
  });
}
