import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final bool isGlassmorphic;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = false,
    this.onBackPressed,
    this.isGlassmorphic = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final appBar = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.primaryLight,
            ),
      ),
      leading: showBackButton
          ? Padding(
              padding: const EdgeInsets.all(AppTheme.spaceS),
              child: ClipOval(
                child: Material(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                  child: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: 16,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                    onPressed: onBackPressed ?? () => Navigator.maybePop(context),
                  ),
                ),
              ),
            )
          : null,
      actions: actions,
    );

    if (!isGlassmorphic) return appBar;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.backgroundDark.withOpacity(0.7)
                : AppColors.backgroundLight.withOpacity(0.7),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE5EFF5),
                width: 1,
              ),
            ),
          ),
          child: appBar,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
