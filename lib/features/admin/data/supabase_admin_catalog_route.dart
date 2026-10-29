/// Maps the existing Admin Web catalog REST calls to the local Supabase
/// `admin-catalog` Edge Function contract. Bulk imports map only when their
/// separate opt-in flag is enabled; otherwise they stay on Express.
class SupabaseAdminCatalogRequest {
  const SupabaseAdminCatalogRequest({
    required this.action,
    this.targetId,
    this.values,
  });

  final String action;
  final String? targetId;
  final Map<String, dynamic>? values;

  Map<String, dynamic> toJson() => {
    'action': action,
    if (targetId != null) 'targetId': targetId,
    if (values != null) 'values': values,
  };
}

SupabaseAdminCatalogRequest? mapSupabaseAdminCatalogRequest(
  String path, {
  required String method,
  dynamic data,
  bool allowCatalog = true,
  bool allowBulkImport = false,
}) {
  final normalizedMethod = method.toUpperCase();
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.decodeComponent)
      .toList(growable: false);
  final values = data is Map ? Map<String, dynamic>.from(data) : null;

  if (segments.length == 2 &&
      segments[0] == 'products' &&
      segments[1] == 'bulk') {
    if (!allowBulkImport || normalizedMethod != 'POST' || values == null) {
      return null;
    }
    final products = values['products'];
    if (products is! List) return null;
    return SupabaseAdminCatalogRequest(
      action: 'bulk_import_products',
      values: {'products': products},
    );
  }
  if (!allowCatalog) return null;
  if (segments.length == 1 && segments.single == 'products') {
    if (normalizedMethod == 'GET') {
      return const SupabaseAdminCatalogRequest(action: 'list_products');
    }
    if (normalizedMethod == 'POST' && values != null) {
      return SupabaseAdminCatalogRequest(
        action: 'create_product',
        values: values,
      );
    }
  }
  if (segments.length == 2 && segments.first == 'products') {
    final targetId = segments[1];
    if (normalizedMethod == 'PUT' && values != null) {
      return SupabaseAdminCatalogRequest(
        action: 'update_product',
        targetId: targetId,
        values: values,
      );
    }
    if (normalizedMethod == 'DELETE') {
      return SupabaseAdminCatalogRequest(
        action: 'deactivate_product',
        targetId: targetId,
      );
    }
  }
  if (segments.length == 1 && segments.single == 'categories') {
    if (normalizedMethod == 'GET') {
      return const SupabaseAdminCatalogRequest(action: 'list_categories');
    }
    if (normalizedMethod == 'POST' && values != null) {
      return SupabaseAdminCatalogRequest(
        action: 'create_category',
        values: values,
      );
    }
  }
  if (segments.length == 2 && segments.first == 'categories') {
    final targetId = segments[1];
    if (normalizedMethod == 'PUT' && values != null) {
      return SupabaseAdminCatalogRequest(
        action: 'update_category',
        targetId: targetId,
        values: values,
      );
    }
    if (normalizedMethod == 'DELETE') {
      return SupabaseAdminCatalogRequest(
        action: 'delete_category',
        targetId: targetId,
      );
    }
  }
  return null;
}
