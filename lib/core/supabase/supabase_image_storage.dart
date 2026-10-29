import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Supabase Storage uploader for the later admin-auth cutover. The Storage
/// policy checks a trusted app_metadata role; user-editable metadata is never
/// accepted as authorization. Existing admin uploads remain on Express until
/// Admin Login issues a Supabase-authenticated admin identity.
class SupabaseImageStorage {
  static const bucket = 'ro-product-images';
  static const maxBytes = 5 * 1024 * 1024;
  static const _allowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  Future<String> upload({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase Storage is not configured.');
    }
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null || user.appMetadata['role'] != 'admin') {
      throw const AuthException('An authenticated administrator is required.');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    if (!_allowedMimeTypes.contains(contentType.toLowerCase())) {
      throw ArgumentError('Use a JPG, PNG, or WEBP image.');
    }
    final path = objectPath.replaceAll('..', '').replaceAll('\\', '/');
    if (path.startsWith('/') || path.isEmpty) {
      throw ArgumentError('A valid relative image path is required.');
    }
    await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType.toLowerCase(),
            upsert: false,
          ),
        );
    return SupabaseConfig.client.storage.from(bucket).getPublicUrl(path);
  }
}
