import 'package:supabase_flutter/supabase_flutter.dart';

/// Client-safe Supabase configuration. Only the publishable/anon key belongs
/// here; service-role keys and database credentials must remain server-side.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const useSupabaseAuth = bool.fromEnvironment(
    'USE_SUPABASE_AUTH',
    defaultValue: false,
  );
  static const useSupabaseCatalog = bool.fromEnvironment(
    'USE_SUPABASE_CATALOG',
    defaultValue: false,
  );
  static const useSupabaseDealerData = bool.fromEnvironment(
    'USE_SUPABASE_DEALER_DATA',
    defaultValue: false,
  );
  static const useSupabaseCheckout = bool.fromEnvironment(
    'USE_SUPABASE_CHECKOUT',
    defaultValue: false,
  );
  static const useSupabaseAdminCatalog = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_CATALOG',
    defaultValue: false,
  );
  static const useSupabaseAdminBulkImport = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_BULK_IMPORT',
    defaultValue: false,
  );
  static const useSupabaseAdminDealerApproval = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_DEALER_APPROVAL',
    defaultValue: false,
  );
  static const useSupabaseAdminDealers = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_DEALERS',
    defaultValue: false,
  );
  static const useSupabaseAdminStats = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_STATS',
    defaultValue: false,
  );
  static const useSupabaseAdminOrders = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_ORDERS',
    defaultValue: false,
  );
  static const useSupabaseAdminAnalytics = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_ANALYTICS',
    defaultValue: false,
  );
  static const useSupabaseAdminOrderStatus = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_ORDER_STATUS',
    defaultValue: false,
  );
  static const useSupabaseAdminShopEnquiries = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_SHOP_ENQUIRIES',
    defaultValue: false,
  );
  static const useSupabaseAdminShopNotifications = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_SHOP_NOTIFICATIONS',
    defaultValue: false,
  );
  static const useSupabaseAdminShopEmployees = bool.fromEnvironment(
    'USE_SUPABASE_ADMIN_SHOP_EMPLOYEES',
    defaultValue: false,
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
  static bool get authEnabled => useSupabaseAuth && isConfigured;
  static bool get catalogEnabled => useSupabaseCatalog && isConfigured;
  // Dealer-owned database access requires a Supabase Auth session so RLS can
  // bind every request to auth.uid(). Legacy Express sessions are not enough.
  static bool get dealerDataEnabled => useSupabaseDealerData && authEnabled;
  // Checkout requires a Supabase Auth identity linked to an approved dealer.
  // It remains independently opt-in; Express is the default fallback.
  static bool get checkoutEnabled => useSupabaseCheckout && authEnabled;
  // Admin catalog writes are routed to a server-authorized Edge Function only
  // after a verified Supabase Auth admin session exists. Each admin area has
  // its own default-off flag; Express remains the default fallback.
  static bool get adminCatalogEnabled =>
      useSupabaseAdminCatalog && isConfigured;
  static bool get adminBulkImportEnabled =>
      useSupabaseAdminBulkImport && isConfigured;
  static bool get adminDealerApprovalEnabled =>
      useSupabaseAdminDealerApproval && isConfigured;
  static bool get adminDealersEnabled =>
      useSupabaseAdminDealers && isConfigured;
  static bool get adminStatsEnabled => useSupabaseAdminStats && isConfigured;
  static bool get adminOrdersEnabled => useSupabaseAdminOrders && isConfigured;
  static bool get adminAnalyticsEnabled =>
      useSupabaseAdminAnalytics && isConfigured;
  static bool get adminOrderStatusEnabled =>
      useSupabaseAdminOrderStatus && isConfigured;
  static bool get adminShopEnquiriesEnabled =>
      useSupabaseAdminShopEnquiries && isConfigured;
  static bool get adminShopNotificationsEnabled =>
      useSupabaseAdminShopNotifications && isConfigured;
  static bool get adminShopEmployeesEnabled =>
      useSupabaseAdminShopEmployees && isConfigured;
  static bool get adminSupabaseEnabled =>
      adminCatalogEnabled ||
      adminBulkImportEnabled ||
      adminDealerApprovalEnabled ||
      adminDealersEnabled ||
      adminStatsEnabled ||
      adminOrdersEnabled ||
      adminAnalyticsEnabled ||
      adminOrderStatusEnabled ||
      adminShopEnquiriesEnabled ||
      adminShopNotificationsEnabled ||
      adminShopEmployeesEnabled;
  static bool get adminCatalogSessionActive =>
      adminSupabaseEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminDealerApprovalSessionActive =>
      adminDealerApprovalEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminDealersSessionActive =>
      adminDealersEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminStatsSessionActive =>
      adminStatsEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminOrdersSessionActive =>
      adminOrdersEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminAnalyticsSessionActive =>
      adminAnalyticsEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminOrderStatusSessionActive =>
      adminOrderStatusEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminShopEnquiriesSessionActive =>
      adminShopEnquiriesEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminShopNotificationsSessionActive =>
      adminShopNotificationsEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get adminShopEmployeesSessionActive =>
      adminShopEmployeesEnabled &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null &&
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  static bool get checkoutSessionActive =>
      checkoutEnabled && Supabase.instance.client.auth.currentSession != null;
  static bool get dealerDataSessionActive =>
      dealerDataEnabled && Supabase.instance.client.auth.currentSession != null;

  static Future<void> initialize() async {
    // Loading the client config is inert: every repository still checks its
    // own default-off feature flag before making a Supabase request. This lets
    // the app validate local URL/key wiring without enabling migration paths.
    if (!isConfigured) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
