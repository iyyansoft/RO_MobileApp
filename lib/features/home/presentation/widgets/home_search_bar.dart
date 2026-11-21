import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/rupee_format.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_image.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../../products/presentation/widgets/cabinet_price_text.dart';

const _blue = Color(0xFF0B6BCB);
const _navy = Color(0xFF0F2544);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _hint = Color(0xFF94A3B8);
const _line = Color(0xFFE3EAF3);

/// Whether [product] matches a search [query].
///
/// Case-insensitive; matches product name, brand, category, SKU and
/// description, understands singular/plural ("filter"/"filters") and common
/// category keywords (pump/booster, pipe/tubing, spare/part, fitting).
bool productMatchesSearch(ProductModel product, String query) {
  final raw = query.trim().toLowerCase();
  if (raw.isEmpty) return false;
  final q = raw.replaceAll(RegExp(r'\s+'), ' ');

  final catId = product.categoryId.toLowerCase();
  final catName = product.categoryName.toLowerCase();
  final name = product.name.toLowerCase();
  final brand = product.brand.toLowerCase();
  final sku = product.sku.toLowerCase();
  final desc = product.description.toLowerCase();

  bool inCategoryOrName(List<String> words) => words.any(
    (w) => catId.contains(w) || catName.contains(w) || name.contains(w),
  );

  // Category keywords.
  if (q.startsWith('filter') && inCategoryOrName(['filter'])) return true;
  if ((q.startsWith('pump') || q.contains('booster')) &&
      inCategoryOrName(['pump'])) {
    return true;
  }
  if (q.startsWith('membrane') && inCategoryOrName(['membrane'])) return true;
  if ((q.startsWith('pipe') || q.contains('tubing')) &&
      inCategoryOrName(['pipe', 'tubing', 'tube'])) {
    return true;
  }
  if ((q.contains('spare') || q.contains('part')) &&
      inCategoryOrName(['spare', 'part'])) {
    return true;
  }
  if ((q.startsWith('accessor') || q.contains('fitting')) &&
      (catId.contains('accessor') ||
          catName.contains('accessor') ||
          catId.contains('connector') ||
          catName.contains('connector') ||
          name.contains('fitting'))) {
    return true;
  }

  // Singular / plural tokens against every searchable field.
  final singular = (q.endsWith('s') && q.length > 2)
      ? q.substring(0, q.length - 1)
      : q;
  final plural = q.endsWith('s') ? q : '${q}s';
  final fields = [name, brand, catName, catId, sku, desc];
  for (final token in {q, singular, plural}) {
    if (token.isEmpty) continue;
    if (fields.any((f) => f.contains(token))) return true;
  }
  return false;
}

/// Lower is better: name prefix, then name, then brand/category, then rest.
int _rank(ProductModel p, String query) {
  final q = query.trim().toLowerCase();
  final name = p.name.toLowerCase();
  if (name.startsWith(q)) return 0;
  if (name.contains(q)) return 1;
  if (p.brand.toLowerCase().contains(q) ||
      p.categoryName.toLowerCase().contains(q)) {
    return 2;
  }
  return 3;
}

/// Matching catalogue products for [query], best matches first.
List<ProductModel> searchProducts(List<ProductModel> products, String query) {
  if (query.trim().isEmpty) return const [];
  final matches = products
      .where((p) => productMatchesSearch(p, query))
      .toList();
  matches.sort((a, b) {
    final r = _rank(a, query).compareTo(_rank(b, query));
    return r != 0 ? r : a.name.compareTo(b.name);
  });
  return matches;
}

/// Premium inline product search for the Home page.
///
/// Searches the live catalogue already loaded from the backend
/// (`catalogProductsProvider` → `/api/products`), so typing never triggers
/// extra network requests. Results appear below the field while typing
/// (debounced), with loading, empty and error states and a clear button.
class HomeSearchBar extends ConsumerStatefulWidget {
  const HomeSearchBar({
    super.key,
    required this.onOpenProduct,
    required this.onAddToCart,
    required this.onOpenFilters,
    this.isDark = false,
    this.debounce = const Duration(milliseconds: 300),
  });

  final ValueChanged<ProductModel> onOpenProduct;
  final ValueChanged<ProductModel> onAddToCart;
  final VoidCallback onOpenFilters;
  final bool isDark;
  final Duration debounce;

  static const placeholder = 'Search RO systems, membranes, pumps, spares...';

  /// Results shown before "View all".
  static const previewCount = 5;

  @override
  ConsumerState<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends ConsumerState<HomeSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _pending = false;
  bool _showAll = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _pending = false;
        _showAll = false;
      });
      return;
    }
    setState(() => _pending = true);
    _debounce = Timer(widget.debounce, () {
      if (!mounted) return;
      setState(() {
        _query = trimmed;
        _pending = false;
        _showAll = false;
      });
    });
  }

  void _search(String text) {
    _controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    _debounce?.cancel();
    setState(() {
      _query = text.trim();
      _pending = false;
      _showAll = false;
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _pending = false;
      _showAll = false;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final catalog = ref.watch(catalogProductsProvider);
    final hasText = _controller.text.trim().isNotEmpty;

    final surface = isDark ? const Color(0xFF132233) : Colors.white;
    final border = _focused
        ? _blue.withValues(alpha: 0.55)
        : (isDark ? const Color(0xFF1E2D3D) : _line);

    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 62,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border, width: _focused ? 1.4 : 1),
        boxShadow: [
          BoxShadow(
            color: (_focused ? _blue : const Color(0xFF0F2850)).withValues(
              alpha: isDark ? 0.25 : (_focused ? 0.12 : 0.06),
            ),
            blurRadius: _focused ? 22 : 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 22,
            color: _focused ? _blue : _muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('home-search-field'),
              controller: _controller,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _search(v);
              },
              textInputAction: TextInputAction.search,
              cursorColor: _blue,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : _ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: HomeSearchBar.placeholder,
                hintMaxLines: 1,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: _hint,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (_pending || (hasText && catalog.isLoading && !catalog.hasValue))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  key: ValueKey('home-search-loading'),
                  strokeWidth: 2,
                  color: _blue,
                ),
              ),
            ),
          if (hasText)
            IconButton(
              tooltip: 'Clear search',
              onPressed: _clear,
              icon: const Icon(Icons.close_rounded, size: 20, color: _muted),
            ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Filters',
            child: Material(
              color: _navy,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('home-search-filter'),
                onTap: widget.onOpenFilters,
                borderRadius: BorderRadius.circular(16),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: hasText
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _resultsPanel(catalog, surface),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _resultsPanel(AsyncValue<List<ProductModel>> catalog, Color surface) {
    final isDark = widget.isDark;
    Widget body;

    if (_pending || (catalog.isLoading && !catalog.hasValue)) {
      body = _PanelMessage(
        key: const ValueKey('home-search-searching'),
        icon: null,
        title: 'Searching products...',
        isDark: isDark,
      );
    } else if (catalog.hasError && !catalog.hasValue) {
      body = _PanelMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Products could not be loaded',
        subtitle: 'Check your connection and pull down to refresh.',
        isDark: isDark,
      );
    } else {
      final results = searchProducts(catalog.value ?? const [], _query);
      if (results.isEmpty) {
        final categories = ref.watch(categoriesProvider);
        body = _PanelMessage(
          key: const ValueKey('home-search-empty'),
          icon: Icons.search_off_rounded,
          title: 'No products match "$_query"',
          subtitle: 'Try a product name, category, brand or SKU.',
          suggestions: categories.map((c) => c.name).toList(),
          onSuggestion: _search,
          isDark: isDark,
        );
      } else {
        final shown = _showAll
            ? results
            : results.take(HomeSearchBar.previewCount).toList();
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${results.length} '
                      '${results.length == 1 ? 'product' : 'products'} found',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ),
                  if (results.length > HomeSearchBar.previewCount)
                    TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(
                        _showAll ? 'Show less' : 'View all ${results.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                itemCount: shown.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 76,
                  color: isDark ? Colors.white10 : const Color(0xFFEEF2F7),
                ),
                itemBuilder: (context, i) => _ResultRow(
                  product: shown[i],
                  isDark: isDark,
                  onTap: () => widget.onOpenProduct(shown[i]),
                  onAdd: () => widget.onAddToCart(shown[i]),
                ),
              ),
            ),
          ],
        );
      }
    }

    return Container(
      key: const ValueKey('home-search-results'),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : _line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2850)
                .withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(color: Colors.transparent, child: body),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.product,
    required this.isDark,
    required this.onTap,
    required this.onAdd,
  });

  final ProductModel product;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.categoryName.isNotEmpty) product.categoryName,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1B2D42)
                    : const Color(0xFFF4F8FC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppImage(
                product.displayImageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.water_drop_rounded, color: _blue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty)
                    Text(
                      meta.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: _blue,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: rupee(product.dealerPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : _ink,
                          ),
                        ),
                        if (product.mrp > product.dealerPrice)
                          TextSpan(
                            text: '  ${rupee(product.mrp)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _muted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        TextSpan(
                          text: product.moqSet
                              ? '   MOQ ${product.moq}'
                              : '   MOQ not set',
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CabinetPriceText(
                    product,
                    fontSize: 11.5,
                    padding: const EdgeInsets.only(top: 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Add to cart',
              child: Material(
                color: _blue.withValues(alpha: 0.1),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAdd,
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.add_rounded, color: _blue, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.suggestions = const [],
    this.onSuggestion,
    this.isDark = false,
  });

  final bool isDark;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _blue, size: 24),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : _ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          ],
          if (suggestions.isNotEmpty && onSuggestion != null) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => onSuggestion!(s),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _navy,
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
