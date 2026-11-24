/// Categories page image rule, identical on every platform (Flutter Web,
/// Android emulator, Android app): a product's picture is shown only when its
/// saved image is a Supabase Storage public URL. Anything else is hidden and
/// the page's existing water-drop placeholder is shown instead:
/// backend pictures (`/api/product-images/...`, also as a full backend URL),
/// static names such as `purifier.jpg` / `cat_pump.jpg`, `/uploads/...`,
/// empty or invalid values and any other web address.
///
/// Used only by the Categories page. The saved image value is never changed
/// and every other screen keeps using it as before.
library;

const _publicStoragePath = '/storage/v1/object/public/';

/// True for `https://<project>.supabase.co/storage/v1/object/public/<bucket>/<file>`.
bool isSupabaseStorageImage(String imageUrl) {
  final text = imageUrl.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) return false;
  final host = uri.host.toLowerCase();
  if (!host.endsWith('.supabase.co') || host == '.supabase.co') return false;
  if (!uri.path.startsWith(_publicStoragePath)) return false;
  // Needs a bucket and a file: <bucket>/<file...>
  final rest = uri.path
      .substring(_publicStoragePath.length)
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  return rest.length >= 2;
}

/// True when the Categories page shows the placeholder instead of the
/// product's own picture. Same answer on every platform.
bool categoriesPageUsesPlaceholder(String imageUrl) =>
    !isSupabaseStorageImage(imageUrl);
