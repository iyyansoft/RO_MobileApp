import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local public Supabase defines initialize the SDK with flags still off',
    () async {
      expect(SupabaseConfig.isConfigured, isTrue);
      expect(SupabaseConfig.useSupabaseAuth, isFalse);
      expect(SupabaseConfig.useSupabaseCatalog, isFalse);
      expect(SupabaseConfig.useSupabaseDealerData, isFalse);
      expect(SupabaseConfig.useSupabaseCheckout, isFalse);
      expect(SupabaseConfig.useSupabaseAdminCatalog, isFalse);
      expect(SupabaseConfig.useSupabaseAdminBulkImport, isFalse);
      expect(SupabaseConfig.useSupabaseAdminDealerApproval, isFalse);
      expect(SupabaseConfig.useSupabaseAdminDealers, isFalse);
      expect(SupabaseConfig.useSupabaseAdminStats, isFalse);
      expect(SupabaseConfig.useSupabaseAdminOrders, isFalse);
      expect(SupabaseConfig.useSupabaseAdminAnalytics, isFalse);
      expect(SupabaseConfig.useSupabaseAdminOrderStatus, isFalse);
      expect(SupabaseConfig.useSupabaseAdminShopEnquiries, isFalse);
      expect(SupabaseConfig.useSupabaseAdminShopNotifications, isFalse);
      expect(SupabaseConfig.useSupabaseAdminShopEmployees, isFalse);
      expect(SupabaseConfig.authEnabled, isFalse);
      expect(SupabaseConfig.catalogEnabled, isFalse);
      expect(SupabaseConfig.dealerDataEnabled, isFalse);
      expect(SupabaseConfig.checkoutEnabled, isFalse);
      expect(SupabaseConfig.adminShopEnquiriesEnabled, isFalse);
      expect(SupabaseConfig.adminShopNotificationsEnabled, isFalse);
      expect(SupabaseConfig.adminShopEmployeesEnabled, isFalse);
      expect(SupabaseConfig.adminSupabaseEnabled, isFalse);

      const preferencesChannel = MethodChannel(
        'plugins.flutter.io/shared_preferences',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => <String, Object>{},
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(preferencesChannel, null),
      );
      await SupabaseConfig.initialize();
      expect(SupabaseConfig.client.auth.currentSession, isNull);
    },
    skip: !SupabaseConfig.isConfigured,
  );
}
