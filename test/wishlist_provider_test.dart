import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/wishlist_provider.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('toggling saves and removes a product', () async {
    final wishlist = WishlistNotifier('dealer@example.test');
    addTearDown(wishlist.dispose);
    await _settle();
    await wishlist.toggle('p1');
    expect(wishlist.contains('p1'), isTrue);
    await wishlist.toggle('p1');
    expect(wishlist.contains('p1'), isFalse);
  });

  test('wishlist survives an app restart / browser refresh', () async {
    final first = WishlistNotifier('dealer@example.test');
    await _settle();
    await first.toggle('p1');
    await first.toggle('p2');
    first.dispose();

    final reopened = WishlistNotifier('dealer@example.test');
    addTearDown(reopened.dispose);
    await _settle();
    await _settle();
    expect(reopened.state, {'p1', 'p2'});
  });

  test('each account has its own wishlist', () async {
    final a = WishlistNotifier('a@example.test');
    await _settle();
    await a.toggle('p1');
    a.dispose();

    final b = WishlistNotifier('b@example.test');
    addTearDown(b.dispose);
    await _settle();
    expect(b.state, isEmpty);
  });
}
