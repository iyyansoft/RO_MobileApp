import '../../../core/network/api_client.dart';

/// The image saved for a category in the Admin Panel, as a full URL, or null
/// when nothing usable is saved.
///
/// A saved value is used when it is a real picture:
///  - a full web address (e.g. a Supabase Storage URL),
///  - a picture on the app's server: `/images/...` (bundled pictures),
///    `/api/product-images/...` (Admin "Upload Image") or `/uploads/...`.
///
/// Old placeholder names stored before Admin category images existed (e.g.
/// `purifier.jpg`, `cat_filter.jpg`) and empty values return null, so the
/// app keeps showing its own picture for that category.
String? adminCategoryImage(String? saved) {
  final value = (saved ?? '').trim();
  if (value.isEmpty) return null;
  final lower = value.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) return value;
  if (lower.startsWith('/images/') ||
      lower.startsWith('/api/product-images/') ||
      lower.startsWith('/uploads/')) {
    return '${Uri.parse(ApiClient.defaultBaseUrl).origin}$value';
  }
  return null;
}
