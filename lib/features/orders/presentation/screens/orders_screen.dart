import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _hasOrders = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Dealer Orders',
        actions: [
          IconButton(
            icon: Icon(_hasOrders ? Icons.filter_list_off_rounded : Icons.checklist_rounded),
            onPressed: () {
              setState(() {
                _hasOrders = !_hasOrders;
              });
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _hasOrders ? _buildOrdersList() : _buildEmptyOrders(),
      ),
    );
  }

  Widget _buildEmptyOrders() {
    return EmptyState(
      key: const ValueKey('empty_orders'),
      title: 'No Wholesale Orders Yet',
      description: 'You haven\'t placed any dealer orders. Start browsing our catalog to place your first wholesale order.',
      icon: Icons.receipt_long_rounded,
      actionText: 'Browse Catalog',
      onActionPressed: () {
        // Switch tab action or simple notification
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigating to products catalog...')),
        );
      },
    );
  }

  Widget _buildOrdersList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      key: const ValueKey('orders_list'),
      padding: const EdgeInsets.all(AppTheme.spaceM),
      itemCount: 3,
      itemBuilder: (context, index) {
        final orderIds = ['#ORD-894812', '#ORD-781290', '#ORD-670189'];
        final dates = ['Aug 28, 2026', 'Aug 15, 2026', 'Jul 30, 2026'];
        final totals = ['₹42,500', '₹1,12,000', '₹15,400'];
        final itemsCounts = [45, 120, 18];
        final statuses = [BadgeStatus.info, BadgeStatus.success, BadgeStatus.warning];
        final statusLabels = ['SHIPPED', 'DELIVERED', 'PENDING PAYMENT'];

        return Card(
          margin: const EdgeInsets.only(bottom: AppTheme.spaceM),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      orderIds[index],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    StatusBadge(
                      label: statusLabels[index],
                      status: statuses[index],
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceS),
                Text(
                  'Placed on ${dates[index]}',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    fontSize: 13,
                  ),
                ),
                const Divider(height: AppTheme.spaceL),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL AMOUNT',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          totals[index],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${itemsCounts[index]} items ordered',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
