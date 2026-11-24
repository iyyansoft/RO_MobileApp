import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../../core/utils/rupee_format.dart';
import '../../../../core/widgets/app_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/wishlist_provider.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/product_model.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../providers/product_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/product_share_sheet.dart';
import '../widgets/cart_actions.dart' show cartErrorText, showAddedToCartToast;
import '../widgets/max_quantity_dialog.dart';
import '../widgets/cabinet_price_text.dart';
import '../../domain/category_price_view.dart';
import '../../../../core/widgets/app_toast.dart';

class ProductDetailsScreen extends ConsumerStatefulWidget {
  final ProductModel product;
  final String? heroTag;

  /// Price format of the category page it was opened from (Cabinets: Cabinet
  /// Price only; RO Systems: Dealer Price + MRP). Opened without a category:
  /// the existing standard display.
  final ProductPriceView priceView;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.heroTag,
    this.priceView = ProductPriceView.standard,
  });

  @override
  ConsumerState<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen>
    with SingleTickerProviderStateMixin {
  late int _quantity;
  int _activeImageIndex = 0;
  bool _isSharing = false;
  late PageController _pageController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Orders start at the MOQ (1 when none is set).
    _quantity = widget.product.minOrderQty;
    _pageController = PageController();
    // Build the WhatsApp share card now, so the Share icon can share it in
    // one tap (browsers allow sharing only right after the tap).
    ProductShareCards.prepare(widget.product, ProductSharer()).ignore();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _incrementQuantity() {
    // Product maximum (PDF quantity): the popup, and the quantity stays.
    if (widget.product.exceedsMaximum(_quantity + 1)) {
      showMaxQuantityDialog(context, widget.product.maxOrderQuantity!);
      return;
    }
    final max = widget.product.stockQuantity;
    if (max != null && _quantity >= max) {
      AppToast.error(context, 'Only $max of ${widget.product.name} in stock.');
      return;
    }
    setState(() {
      _quantity++;
    });
  }

  void _decrementQuantity() {
    // The smallest selectable quantity is 1.
    if (_quantity > 1) {
      setState(() {
        _quantity--;
      });
    }
  }

  void _openImageZoomModal(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black.withValues(alpha: 0.9),
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: AppImage(imagePath, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Theme helpers -------------------------------------------------------
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE2E8F0);

  /// Clean white card with a light border and subtle shadow.
  BoxDecoration _card(bool isDark, {double radius = 18}) => BoxDecoration(
    color: isDark ? AppColors.surfaceDark : Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : _line),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF0F2850).withValues(alpha: isDark ? 0.2 : 0.05),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final allProducts = ref.watch(allProductsProvider);
    final relatedProducts = allProducts
        .where(
          (p) =>
              p.id != widget.product.id &&
              p.categoryId == widget.product.categoryId,
        )
        .toList();
    final images = widget.product.allImages;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF5F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          // Opened from a link / after refresh there is nothing to go back
          // to: show the catalogue instead.
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : GoRouter.of(context).go('/products'),
        ),
        title: Text(
          widget.product.brand.toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: primaryColor,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          Builder(
            builder: (context) {
              final saved = ref
                  .watch(wishlistProvider)
                  .contains(widget.product.id);
              return IconButton(
                tooltip: saved ? 'Remove from wishlist' : 'Add to wishlist',
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  color: saved ? Colors.redAccent : null,
                ),
                onPressed: () {
                  ref.read(wishlistProvider.notifier).toggle(widget.product.id);
                  AppToast.success(
                    context,
                    saved ? 'Removed from wishlist' : 'Saved to wishlist',
                  );
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Share product',
            icon: const Icon(Icons.share_outlined),
            onPressed: _isSharing
                ? null
                : () async {
                    setState(() => _isSharing = true);
                    try {
                      // One tap: image + every detail in one share.
                      await shareProductInOneClick(
                        context,
                        product: widget.product,
                      );
                    } finally {
                      if (mounted) setState(() => _isSharing = false);
                    }
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final related = _buildRelatedProducts(
              context,
              relatedProducts,
              isDark,
              wide,
            );

            if (wide) {
              // Desktop: centred 1300 px container, image left, details right.
              return SingleChildScrollView(
                child: ResponsiveContentWrapper(
                  maxWidth: 1300,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 42, // image column
                            child: _buildImageGallery(
                              context,
                              images,
                              isDark,
                              primaryColor,
                              large: true,
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            flex: 58, // details column
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeaderInfo(isDark, large: true),
                                const SizedBox(height: 18),
                                _buildPriceCard(
                                  isDark,
                                  primaryColor,
                                  large: true,
                                ),
                                const SizedBox(height: 14),
                                _buildQuantityCard(isDark, primaryColor),
                                const SizedBox(height: 16),
                                _buildActionButtons(
                                  context,
                                  primaryColor,
                                  height: 52,
                                ),
                                const SizedBox(height: 18),
                                _buildDetailsCard(isDark, primaryColor),
                              ],
                            ),
                          ),
                        ],
                      ),
                      related,
                    ],
                  ),
                ),
              );
            }

            // Mobile / narrow: image first, then details; actions fixed below.
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: _buildImageGallery(
                            context,
                            images,
                            isDark,
                            primaryColor,
                            large: false,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeaderInfo(isDark, large: false),
                              const SizedBox(height: 14),
                              _buildPriceCard(
                                isDark,
                                primaryColor,
                                large: false,
                              ),
                              const SizedBox(height: 12),
                              _buildQuantityCard(isDark, primaryColor),
                              const SizedBox(height: 14),
                              _buildDetailsCard(isDark, primaryColor),
                            ],
                          ),
                        ),
                        related,
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                // Fixed bottom action area (Add to Cart & Buy Now).
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDark
                        : AppColors.surfaceLight,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? const Color(0xFF1E2D3D) : _line,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _buildActionButtons(context, primaryColor, height: 48),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Badges, name, SKU and category.
  Widget _buildHeaderInfo(bool isDark, {required bool large}) {
    final p = widget.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildStockBadge(p.stockStatus),
            const Spacer(),
            const Icon(Icons.star_rounded, size: 17, color: Color(0xFFFFB300)),
            const SizedBox(width: 3),
            Text(
              '${p.rating}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: isDark ? Colors.white : _ink,
              ),
            ),
            Text(
              ' (${p.reviewCount})',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        SizedBox(height: large ? 14 : 10),
        Text(
          p.name,
          style: TextStyle(
            fontSize: large ? 28 : 21,
            fontWeight: FontWeight.w900,
            height: 1.2,
            letterSpacing: -0.4,
            color: isDark ? Colors.white : _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'SKU: ${p.sku} • Category: ${p.categoryName}',
          style: TextStyle(
            fontSize: large ? 13 : 12,
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Dealer Price (with struck MRP), Cabinet Price where it applies, MOQ.
  Widget _buildPriceCard(
    bool isDark,
    Color primaryColor, {
    required bool large,
  }) {
    final p = widget.product;
    final view = widget.priceView;
    // Cabinets page: the Cabinet Price only (no Dealer Price, MRP or
    // discount). Display only; the cart still uses the product's price.
    final cabinetOnly = view.cabinetOnly(p);
    return Container(
      padding: EdgeInsets.all(large ? 20 : 16),
      decoration: _card(isDark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cabinetOnly ? 'Cabinet Price' : 'Dealer Price (Excl. GST)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      rupee(cabinetOnly ? p.cabinetPrice! : p.dealerPrice),
                      key: ValueKey(
                        cabinetOnly
                            ? 'details-cabinet-price'
                            : 'details-dealer-price',
                      ),
                      style: TextStyle(
                        fontSize: large ? 32 : 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : _ink,
                      ),
                    ),
                    if (!cabinetOnly && p.mrp > p.dealerPrice)
                      Text(
                        'MRP ${rupee(p.mrp)}',
                        key: const ValueKey('details-mrp'),
                        style: TextStyle(
                          fontSize: large ? 15 : 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                ),
                if (view.showsCabinetLine(p))
                  CabinetPriceText(
                    p,
                    fontSize: large ? 16 : 15,
                    padding: const EdgeInsets.only(top: 6),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
            ),
            child: Text(
              p.moqLabel(),
              style: TextStyle(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Quantity selector with limits and the running total.
  Widget _buildQuantityCard(bool isDark, Color primaryColor) {
    final p = widget.product;
    final totalPrice = p.dealerPrice * _quantity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(isDark),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Order Quantity',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
                if (p.isBelowMoq)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      p.orderBlockedReason!,
                      key: const ValueKey('below-moq-note'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  )
                else if (p.canOrder && p.maxOrderQty != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      p.maxOrderQuantity != null
                          ? 'You can order 1 to ${p.maxOrderQty}'
                          : '${p.maxOrderQty} in stock',
                      key: const ValueKey('quantity-limit-note'),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                // The total is Dealer Price x quantity, so the Cabinets view
                // (which shows no Dealer Price) leaves it to the cart.
                if (!widget.priceView.cabinetOnly(p)) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Total: ${rupee(totalPrice)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: primaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Minus / Counter / Plus
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white10 : _line),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  onPressed: _decrementQuantity,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 42,
                    minHeight: 42,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '$_quantity',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: _incrementQuantity,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 42,
                    minHeight: 42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Add to Cart and Buy Now (both disabled for stock 0).
  Widget _buildActionButtons(
    BuildContext context,
    Color primaryColor, {
    required double height,
  }) {
    final p = widget.product;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: OutlinedButton.icon(
              // Stock 0: neither Add to Cart nor Buy Now.
              onPressed: !p.canOrder
                  ? null
                  : () {
                      _handleAddToCartAnimation(context);
                    },
              style: OutlinedButton.styleFrom(
                // Grey when disabled (stock 0), like Buy Now.
                side: BorderSide(
                  color: !p.canOrder ? Colors.grey.shade400 : primaryColor,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                Icons.add_shopping_cart_rounded,
                size: 19,
                color: !p.canOrder ? Colors.grey.shade500 : primaryColor,
              ),
              label: Text(
                p.isOutOfStock
                    ? 'Out of Stock'
                    : p.isBelowMoq
                    ? 'Below MOQ'
                    : 'Add to Cart',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: !p.canOrder ? Colors.grey.shade600 : primaryColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: height,
            child: ElevatedButton.icon(
              onPressed: !p.canOrder
                  ? null
                  : () async {
                      // Buy Now: add quietly and go straight to checkout.
                      final added = await _handleAddToCartAnimation(
                        context,
                        notify: false,
                      );
                      if (added && context.mounted) {
                        context.push('/checkout');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.flash_on_rounded, size: 19),
              label: const Text(
                'Buy Now',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Overview / Specifications / Features in one card, sized to its content.
  Widget _buildDetailsCard(bool isDark, Color primaryColor) {
    final p = widget.product;
    final body = isDark ? Colors.white70 : const Color(0xFF334155);
    final Widget content = switch (_tabController.index) {
      1 =>
        p.specifications.isEmpty
            ? Text(
                'No specifications listed.',
                style: TextStyle(fontSize: 13, color: body),
              )
            : Column(
                children: [
                  for (final e in p.specifications.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFF1F5F9),
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      2 =>
        p.features.isEmpty
            ? Text(
                'No features listed.',
                style: TextStyle(fontSize: 13, color: body),
              )
            : Column(
                children: [
                  for (final feat in p.features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      _ => Text(
        p.description.trim().isEmpty
            ? 'No description available.'
            : p.description,
        style: TextStyle(fontSize: 13.5, height: 1.55, color: body),
      ),
    };
    return Container(
      decoration: _card(isDark),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primaryColor,
            indicatorWeight: 3,
            dividerColor: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Specifications'),
              Tab(text: 'Features'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey('details-tab-${_tabController.index}'),
                child: Align(alignment: Alignment.topLeft, child: content),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Related Category Products" strip (same behaviour as before).
  Widget _buildRelatedProducts(
    BuildContext context,
    List<ProductModel> relatedProducts,
    bool isDark,
    bool wide,
  ) {
    if (relatedProducts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 0 : 16, wide ? 32 : 20, 16, 12),
          child: Text(
            'Related Category Products',
            style: TextStyle(
              fontSize: wide ? 19 : 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : _ink,
            ),
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 16),
            itemCount: relatedProducts.length,
            itemBuilder: (context, index) {
              final relProduct = relatedProducts[index];
              return Container(
                width: 160,
                margin: const EdgeInsets.only(right: 12),
                child: ProductCard(
                  product: relProduct,
                  isGrid: true,
                  priceView: widget.priceView,
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => ProductDetailsScreen(
                          product: relProduct,
                          priceView: widget.priceView,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Large image on a clean white card, zoom on tap, thumbnails below.
  Widget _buildImageGallery(
    BuildContext context,
    List<String> images,
    bool isDark,
    Color primaryColor, {
    required bool large,
  }) {
    final thumb = large ? 72.0 : 54.0;
    return Container(
      padding: EdgeInsets.all(large ? 16 : 12),
      decoration: _card(isDark, radius: 22),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: large ? 520 : 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) {
                    setState(() {
                      _activeImageIndex = idx;
                    });
                  },
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: GestureDetector(
                        onTap: () =>
                            _openImageZoomModal(context, images[index]),
                        child: Padding(
                          // Slightly smaller product image on desktop; same box height.
                          padding: EdgeInsets.all(large ? 48 : 18),
                          child: Hero(
                            tag: index == 0 && widget.heroTag != null
                                ? widget.heroTag!
                                : 'product_img_${widget.product.id}_$index',
                            child: AppImage(
                              images[index],
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.water_drop_rounded,
                                size: 90,
                                color: primaryColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.zoom_in_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tap to Zoom',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Thumbnails strip
          SizedBox(
            height: thumb + 4,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                primary: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(images.length, (idx) {
                      final isSelected = _activeImageIndex == idx;
                      return GestureDetector(
                        key: ValueKey('product-thumbnail-$idx'),
                        onTap: () {
                          _pageController.animateToPage(
                            idx,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: thumb,
                            height: thumb,
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceDark
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark ? Colors.white10 : _line),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: AppImage(images[idx], fit: BoxFit.contain),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockBadge(StockStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case StockStatus.inStock:
        bg = const Color(0xFF10B981).withValues(alpha: 0.12);
        fg = const Color(0xFF10B981);
        break;
      case StockStatus.lowStock:
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
        fg = const Color(0xFFF59E0B);
        break;
      case StockStatus.outOfStock:
        bg = const Color(0xFF64748B).withValues(alpha: 0.12);
        fg = const Color(0xFF64748B);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w900),
      ),
    );
  }

  /// Adds the selected quantity. Success: the compact "added" toast (not for
  /// Buy Now, which goes straight to checkout). Failure: the max-quantity
  /// popup or a compact error toast.
  Future<bool> _handleAddToCartAnimation(
    BuildContext context, {
    bool notify = true,
  }) async {
    try {
      await ref
          .read(cartProvider.notifier)
          .addToCart(widget.product, quantity: _quantity);
    } catch (e) {
      if (context.mounted && !showMaxQuantityDialogFor(context, e)) {
        AppToast.error(context, cartErrorText(e));
      }
      return false;
    }
    if (notify && context.mounted) showAddedToCartToast(context);
    return true;
  }
}
