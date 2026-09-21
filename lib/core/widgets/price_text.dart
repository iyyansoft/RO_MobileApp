import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PriceText extends StatelessWidget {
  final double price;
  final double? originalPrice;
  final String currency;
  final String? suffix;
  final double fontSize;
  final bool isWholesale;

  const PriceText({
    super.key,
    required this.price,
    this.originalPrice,
    this.currency = '₹',
    this.suffix,
    this.fontSize = 18.0,
    this.isWholesale = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final formattedPrice = '$currency${price.toStringAsFixed(0)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formattedPrice,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize,
                    color: primaryTextColor,
                  ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 2),
              Text(
                suffix!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      fontSize: fontSize * 0.65,
                    ),
              ),
            ],
          ],
        ),
        if (originalPrice != null && originalPrice! > price) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$currency${originalPrice!.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: isDark ? AppColors.textSecondaryDark.withOpacity(0.6) : AppColors.textSecondaryLight.withOpacity(0.6),
                      fontSize: fontSize * 0.75,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                '${(((originalPrice! - price) / originalPrice!) * 100).toStringAsFixed(0)}% OFF',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.successDark : AppColors.successLight,
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize * 0.65,
                    ),
              ),
            ],
          ),
        ],
        if (isWholesale) ...[
          const SizedBox(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.accentDark : AppColors.primaryLight).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'WHOLESALE PRICE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
