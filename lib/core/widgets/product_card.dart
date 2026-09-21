import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'price_text.dart';
import 'status_badge.dart';

class ProductCard extends StatefulWidget {
  final String title;
  final String imageUrl;
  final double price;
  final double? originalPrice;
  final int minOrderQty;
  final bool isAvailable;
  final String brand;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const ProductCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.price,
    this.originalPrice,
    required this.minOrderQty,
    this.isAvailable = true,
    required this.brand,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _isHovered ? (Matrix4.identity()..translate(0, -4)) : Matrix4.identity(),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            boxShadow: _isHovered 
                ? (isDark ? AppTheme.softShadowDark : AppTheme.softShadowLight)
                : [],
            border: Border.all(
              color: _isHovered 
                  ? (isDark ? AppColors.accentDark.withOpacity(0.5) : AppColors.primaryLight.withOpacity(0.5))
                  : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE5EFF5)),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image container
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A2633) : const Color(0xFFF0F6FA),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppTheme.radiusM - 1),
                          topRight: Radius.circular(AppTheme.radiusM - 1),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppTheme.radiusM - 1),
                          topRight: Radius.circular(AppTheme.radiusM - 1),
                        ),
                        child: widget.imageUrl.startsWith('http')
                            ? Image.network(
                                widget.imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (c, o, s) => _buildPlaceholderImage(),
                              )
                            : _buildPlaceholderImage(),
                      ),
                    ),
                    // Status badge overlay
                    Positioned(
                      top: AppTheme.spaceS,
                      left: AppTheme.spaceS,
                      child: StatusBadge(
                        label: widget.isAvailable ? 'IN STOCK' : 'OUT OF STOCK',
                        status: widget.isAvailable ? BadgeStatus.success : BadgeStatus.error,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Product Info
              Padding(
                padding: const EdgeInsets.all(AppTheme.spaceM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.brand.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.accentDark : AppColors.secondaryLight,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: AppTheme.spaceS),
                    
                    // Min Order Qty
                    Text(
                      'MOQ: ${widget.minOrderQty} units',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: AppTheme.spaceM),
                    
                    // Price & Action
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: Alignment.end,
                      children: [
                        Flexible(
                          child: PriceText(
                            price: widget.price,
                            originalPrice: widget.originalPrice,
                            fontSize: 16.0,
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onAddToCart,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? AppColors.accentDark.withOpacity(0.1) : AppColors.primaryLight.withOpacity(0.1),
                            ),
                            child: Icon(
                              Icons.add_shopping_cart_outlined,
                              size: 18,
                              color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Center(
      child: Icon(
        Icons.water_drop_outlined,
        size: 40,
        color: AppColors.secondaryLight.withOpacity(0.4),
      ),
    );
  }
}
