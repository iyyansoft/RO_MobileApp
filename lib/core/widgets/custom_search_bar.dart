import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CustomSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final VoidCallback? onFilterTap;

  const CustomSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'Search RO systems, filters, spares...',
    this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        boxShadow: isDark ? AppTheme.softShadowDark : AppTheme.softShadowLight,
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE5EFF5),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
          suffixIcon: onFilterTap != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 24,
                      width: 1,
                      color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE5EFF5),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.tune_rounded,
                        color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                      ),
                      onPressed: onFilterTap,
                    ),
                  ],
                )
              : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: AppTheme.spaceM - 2,
            horizontal: AppTheme.spaceS,
          ),
        ),
      ),
    );
  }
}
