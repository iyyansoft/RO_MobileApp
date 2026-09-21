import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/product_provider.dart';

class SortBottomSheet extends ConsumerWidget {
  const SortBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentOption = ref.watch(productFilterProvider).sortOption;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle indicator
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sort Products By',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          ...SortOption.values.map((option) {
            final isSelected = currentOption == option;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                option.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ),
              trailing: isSelected
                  ? Icon(Icons.check_circle_rounded, color: primaryColor)
                  : const Icon(Icons.circle_outlined, color: Colors.grey),
              onTap: () {
                ref.read(productFilterProvider.notifier).setSortOption(option);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
