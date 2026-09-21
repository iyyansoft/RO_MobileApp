import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum BadgeStatus {
  success,
  warning,
  error,
  info,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeStatus status;

  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case BadgeStatus.success:
        backgroundColor = isDark 
            ? AppColors.successDark.withOpacity(0.15) 
            : AppColors.successLight.withOpacity(0.12);
        textColor = isDark ? AppColors.successDark : AppColors.successLight;
        break;
      case BadgeStatus.warning:
        backgroundColor = isDark 
            ? AppColors.warningDark.withOpacity(0.15) 
            : AppColors.warningLight.withOpacity(0.12);
        textColor = isDark ? AppColors.warningDark : AppColors.warningLight;
        break;
      case BadgeStatus.error:
        backgroundColor = isDark 
            ? AppColors.errorDark.withOpacity(0.15) 
            : AppColors.errorLight.withOpacity(0.12);
        textColor = isDark ? AppColors.errorDark : AppColors.errorLight;
        break;
      case BadgeStatus.info:
        backgroundColor = isDark 
            ? AppColors.accentDark.withOpacity(0.15) 
            : AppColors.primaryLight.withOpacity(0.12);
        textColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
