import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/product_model.dart';
import 'product_provider.dart';

/// Saved product ids for the signed-in dealer.
///
/// Shared by Web and Android. Stored per account on the device (secure
/// storage), so it survives restarts and browser refreshes and is never mixed
/// between accounts. The backend has no wishlist table yet, so the list does
/// not sync between a dealer's devices.
class WishlistNotifier extends StateNotifier<Set<String>> {
  WishlistNotifier(this._accountKey, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      super(const {}) {
    _load();
  }

  final String _accountKey;
  final FlutterSecureStorage _storage;

  String get _key => 'wishlist_$_accountKey';

  Future<void> _load() async {
    if (_accountKey.isEmpty) return;
    try {
      final saved = await _storage.read(key: _key);
      if (saved == null || !mounted) return;
      final ids = (jsonDecode(saved) as List).map((e) => '$e').toSet();
      // Keep anything toggled before loading finished.
      state = {...ids, ...state};
    } catch (_) {
      // Corrupt or unavailable storage: start with an empty wishlist.
    }
  }

  bool contains(String productId) => state.contains(productId);

  Future<void> toggle(String productId) async {
    final next = {...state};
    if (!next.remove(productId)) next.add(productId);
    state = next;
    await _save();
  }

  Future<void> remove(String productId) async {
    if (!state.contains(productId)) return;
    state = {...state}..remove(productId);
    await _save();
  }

  Future<void> _save() async {
    if (_accountKey.isEmpty) return;
    try {
      await _storage.write(key: _key, value: jsonEncode(state.toList()));
    } catch (_) {
      // The in-memory wishlist still works if storage is unavailable.
    }
  }
}

final wishlistProvider = StateNotifierProvider<WishlistNotifier, Set<String>>((
  ref,
) {
  final user = ref.watch(authProvider.select((a) => a.currentUser));
  final account = (user?.email ?? '').trim().toLowerCase();
  return WishlistNotifier(account);
});

/// Wishlist products that still exist in the live catalogue, in catalogue
/// order.
final wishlistProductsProvider = Provider<List<ProductModel>>((ref) {
  final ids = ref.watch(wishlistProvider);
  if (ids.isEmpty) return const [];
  final products = ref.watch(allProductsProvider);
  return products.where((p) => ids.contains(p.id)).toList();
});
