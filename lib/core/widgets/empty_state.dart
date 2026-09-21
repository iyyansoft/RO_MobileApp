import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';

class EmptyState extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onActionPressed;

  const EmptyState({
    super.key,
    this.title = 'No items found',
    this.description = 'It looks like there is nothing in this section right now.',
    this.icon = Icons.water_drop_outlined,
    this.actionText,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Water drop animation/ripple effect
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isDark ? AppColors.accentDark : AppColors.primaryLight).withOpacity(0.06),
                  ),
                ),
                Container(
                  height: 70,
                  width: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isDark ? AppColors.accentDark : AppColors.primaryLight).withOpacity(0.12),
                  ),
                ),
                Icon(
                  icon,
                  size: 40,
                  color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceL),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppTheme.spaceS),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
            ),
            if (actionText != null && onActionPressed != null) ...[
              const SizedBox(height: AppTheme.spaceXL),
              PrimaryButton(
                text: actionText!,
                onPressed: onActionPressed!,
                width: 200,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
