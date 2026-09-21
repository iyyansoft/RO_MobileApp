import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CategoryCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isSelected;

  const CategoryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Water drop or bubble inspired style
    final Color activeColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final Color inactiveBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final Color activeBg = isDark ? AppColors.secondaryDark.withOpacity(0.2) : AppColors.primaryLight.withOpacity(0.08);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: 80,
          margin: const EdgeInsets.only(right: AppTheme.spaceS),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: widget.isSelected ? activeBg : inactiveBg,
                  borderRadius: BorderRadius.circular(widget.isSelected || _isHovered ? AppTheme.radiusL : AppTheme.radiusM),
                  border: Border.all(
                    color: widget.isSelected || _isHovered
                        ? activeColor
                        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE5EFF5)),
                    width: 1.5,
                  ),
                  boxShadow: widget.isSelected || _isHovered
                      ? (isDark ? AppTheme.softShadowDark : AppTheme.softShadowLight)
                      : [],
                ),
                child: Icon(
                  widget.icon,
                  size: 28,
                  color: widget.isSelected || _isHovered
                      ? activeColor
                      : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                ),
              ),
              const SizedBox(height: AppTheme.spaceS),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: widget.isSelected
                          ? activeColor
                          : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
