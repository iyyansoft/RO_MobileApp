import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../products/domain/models/category_model.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../domain/bulk_catalog.dart';
import '../bulk_cart_actions.dart';
import '../widgets/bulk_product_card.dart';

const _blue = Color(0xFF0B5FC4);
const _deepBlue = Color(0xFF0B4FB8);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE3EAF3);

/// Bulk Orders: Membranes, Filters & Cartridges, Pipes & Tubing and Spare
/// Parts & Valves only, showing the products that have a bulk offer, with
/// bulk prices and pack-step quantities. The normal Categories page is not
/// used here and is unchanged.
class BulkOrdersScreen extends ConsumerStatefulWidget {
  const BulkOrdersScreen({super.key, this.initialCategoryId});

  static const path = '/bulk-orders';

  /// Category to show first (`?category=` in the URL), e.g. "filters".
  final String? initialCategoryId;

  @override
  ConsumerState<BulkOrdersScreen> createState() => _BulkOrdersScreenState();
}

class _BulkOrdersScreenState extends ConsumerState<BulkOrdersScreen> {
  late String? _selectedId = widget.initialCategoryId;

  @override
  void didUpdateWidget(covariant BulkOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategoryId != oldWidget.initialCategoryId &&
        widget.initialCategoryId != null) {
      _selectedId = widget.initialCategoryId;
    }
  }

  void _select(String id) {
    setState(() => _selectedId = id);
    // Keep the tab in the address, so refresh and Back keep it too.
    context.go(bulkOrdersLocation(id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catalog = ref.watch(catalogProductsProvider);
    final categories = bulkCategories(ref.watch(categoriesProvider));
    final products = ref.watch(allProductsProvider);
    final counts = {
      for (final c in categories) c.id: bulkProductsIn(c, products).length,
    };
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    CategoryModel? selected;
    if (categories.isNotEmpty) {
      selected = categories.firstWhere(
        (c) => c.id == _selectedId,
        orElse: () => categories.firstWhere(
          (c) => (counts[c.id] ?? 0) > 0,
          orElse: () => categories.first,
        ),
      );
    }
    final shown = selected == null
        ? const <ProductModel>[]
        : bulkProductsIn(selected, products);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A1118)
          : const Color(0xFFF4F7FC),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final pad = width >= 1000 ? 40.0 : (width >= 600 ? 24.0 : 16.0);
            final content = width > 1320 ? 1240.0 : width - pad * 2;
            final columns = content >= 960 ? 3 : (content >= 620 ? 2 : 1);
            const gap = 18.0;
            final cardWidth = (content - gap * (columns - 1)) / columns;
            return SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: content,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      _Header(
                        total: total,
                        isDark: isDark,
                        onBack: () => context.canPop()
                            ? context.pop()
                            : context.go('/home'),
                      ),
                      const SizedBox(height: 18),
                      // Tabs: one scrollable row (fits on desktop, swipes on
                      // phones).
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        child: Row(
                          children: [
                            for (final c in categories) ...[
                              _CategoryTab(
                                key: ValueKey('bulk-category-${c.id}'),
                                label: c.name,
                                count: counts[c.id] ?? 0,
                                selected: c.id == selected?.id,
                                isDark: isDark,
                                onTap: () => _select(c.id),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.015),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('bulk-content-${selected?.id}'),
                          child: catalog.isLoading && !catalog.hasValue
                              ? const Padding(
                                  padding: EdgeInsets.all(48),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : shown.isEmpty
                              ? _Empty(
                                  text: selected == null
                                      ? 'Bulk Orders will be available soon.'
                                      : 'No bulk offers in ${selected.name} yet.',
                                  isDark: isDark,
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${shown.length} Bulk Products in ${selected!.name}',
                                      key: const ValueKey('bulk-count'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : _ink,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final product in shown)
                                          SizedBox(
                                            width: cardWidth,
                                            height: BulkProductCard.extent,
                                            child: BulkProductCard(
                                              key: ValueKey(
                                                'bulk-${product.id}',
                                              ),
                                              product: product,
                                              isDark: isDark,
                                              onAddToCart: (qty) =>
                                                  addBulkToCart(
                                                    context,
                                                    ref,
                                                    product,
                                                    qty,
                                                  ),
                                              onOpen: () => context.go(
                                                bulkProductLocation(
                                                  product.id,
                                                  selected?.id,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Compact page header: back, small box icon, title, subtitle, total.
class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.isDark,
    required this.onBack,
  });

  final int total;
  final bool isDark;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          style: IconButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF132233) : Colors.white,
            side: BorderSide(color: isDark ? const Color(0xFF1E2D3D) : _line),
          ),
          icon: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: isDark ? Colors.white : _ink,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _deepBlue,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _deepBlue.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bulk Orders',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: isDark ? Colors.white : _ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Wholesale prices for bulk purchases.',
                style: TextStyle(fontSize: 13.5, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
    final count = Container(
      key: const ValueKey('bulk-total'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$total bulk products',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: _blue,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 560
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                count,
              ],
            )
          : title,
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : (isDark ? Colors.white : _ink);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? _deepBlue
            : (isDark ? const Color(0xFF132233) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? _deepBlue
              : (isDark ? const Color(0xFF1E2D3D) : _line),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: _deepBlue.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.2)
                        : _blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : _blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(48),
    child: Column(
      children: [
        const Icon(Icons.inventory_2_outlined, size: 44, color: _muted),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : _muted,
          ),
        ),
      ],
    ),
  );
}
