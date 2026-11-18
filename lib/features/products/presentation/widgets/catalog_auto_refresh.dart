import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/category_model.dart';
import '../../domain/models/product_model.dart';
import '../providers/product_provider.dart';

/// Keeps the customer catalog in step with the admin panel.
///
/// The catalog providers load once and are kept for the whole session, so a
/// product the admin adds (singly or by bulk upload) would otherwise only show
/// after a full reload. This widget re-reads the same `/api/products` and
/// `/api/categories` endpoints:
///  * when the app (or browser tab) comes back to the foreground, and
///  * every [interval] while it is in the foreground.
///
/// Screens only rebuild when something actually changed, and the data already
/// on screen stays visible (no loading skeleton) while the check runs. A failed
/// check is ignored; an earlier failed load is retried by the next check.
class CatalogAutoRefresh extends ConsumerStatefulWidget {
  const CatalogAutoRefresh({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 30),
  });

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<CatalogAutoRefresh> createState() => _CatalogAutoRefreshState();
}

class _CatalogAutoRefreshState extends ConsumerState<CatalogAutoRefresh> {
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _startTimer();
        checkNow();
      },
      onHide: _stopTimer,
    );
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => checkNow());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(CatalogAutoRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval && _timer != null) _startTimer();
  }

  Future<void> checkNow() async {
    if (_checking || !mounted) return;
    final productsNow = ref.read(catalogProductsProvider);
    final categoriesNow = ref.read(catalogCategoriesProvider);
    // The first load is still running; nothing to compare yet.
    if (productsNow.isLoading &&
        !productsNow.hasValue &&
        !productsNow.hasError) {
      return;
    }
    _checking = true;
    try {
      final results = await Future.wait<Object>([
        ref.read(catalogProductsLoaderProvider)(),
        ref.read(catalogCategoriesLoaderProvider)(),
      ]);
      if (!mounted) return;
      final products = results[0] as List<ProductModel>;
      final categories = results[1] as List<CategoryModel>;

      final productsChanged =
          !productsNow.hasValue ||
          productsNow.hasError ||
          productCatalogSignature(productsNow.requireValue) !=
              productCatalogSignature(products);
      final categoriesChanged =
          !categoriesNow.hasValue ||
          categoriesNow.hasError ||
          categoryCatalogSignature(categoriesNow.requireValue) !=
              categoryCatalogSignature(categories);

      final handOff = ref.read(catalogHandOffProvider);
      if (productsChanged) {
        handOff.products = products;
        ref.invalidate(catalogProductsProvider);
      }
      if (categoriesChanged) {
        handOff.categories = categories;
        ref.invalidate(catalogCategoriesProvider);
      }
    } catch (_) {
      // Offline or the backend is waking up: keep showing the current data.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
