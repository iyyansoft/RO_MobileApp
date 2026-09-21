import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';

class ErrorState extends StatelessWidget {
  final String title;
  final String errorMessage;
  final IconData icon;
  final String actionText;
  final VoidCallback onRetry;

  const ErrorState({
    super.key,
    this.title = 'Connection Issue',
    this.errorMessage = 'We couldn\'t load this content. Please verify your connection and try again.',
    this.icon = Icons.cloud_off_rounded,
    this.actionText = 'Retry Connection',
    required this.onRetry,
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
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isDark ? AppColors.errorDark : AppColors.errorLight).withOpacity(0.06),
                  ),
                ),
                Container(
                  height: 70,
                  width: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isDark ? AppColors.errorDark : AppColors.errorLight).withOpacity(0.12),
                  ),
                ),
                Icon(
                  icon,
                  size: 40,
                  color: isDark ? AppColors.errorDark : AppColors.errorLight,
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
              errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
            ),
            const SizedBox(height: AppTheme.spaceXL),
            PrimaryButton(
              text: actionText,
              onPressed: onRetry,
              width: 220,
            ),
          ],
        ),
      ),
    );
  }
}
