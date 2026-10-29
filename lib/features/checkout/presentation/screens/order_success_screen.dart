import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/checkout_provider.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  final bool withGst;
  final PaymentMethodType paymentMethod;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    this.withGst = false,
    this.paymentMethod = PaymentMethodType.cashOnDelivery,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success Animation Circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(0xFF10B981),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 64,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Success Message
                  Text(
                    'B2B Wholesale Order Placed!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your order has been saved. View your orders to check its status and invoice.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Order Summary Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDark
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF1E2D3D)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildRow(
                          'Order ID',
                          orderId,
                          isHighlight: true,
                          primaryColor: primaryColor,
                        ),
                        const Divider(height: 20),
                        _buildRow(
                          'Estimated Dispatch',
                          'Express (Within 24 Hours)',
                        ),
                        const Divider(height: 20),
                        _buildRow(
                          'GST Invoice Status',
                          withGst ? 'GST Invoice Generated' : 'Without GST',
                          statusColor: const Color(0xFF10B981),
                        ),
                        const Divider(height: 20),
                        _buildRow('Payment Method', paymentMethod.label),
                        const Divider(height: 20),
                        _buildRow(
                          'Payment Status',
                          paymentMethod == PaymentMethodType.cashOnDelivery
                              ? 'Due on Delivery'
                              : 'Paid',
                        ),
                      ],
                    ),
                  ),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.go('/orders');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.local_shipping_rounded),
                      label: const Text(
                        'Track Order Status',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        context.go('/home');
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Return to Home Dashboard'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? primaryColor,
    Color? statusColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        );
        final valueText = Text(
          value,
          textAlign: constraints.maxWidth < 300
              ? TextAlign.left
              : TextAlign.right,
          style: TextStyle(
            fontSize: isHighlight ? 14 : 12.5,
            fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w700,
            color: statusColor ?? (isHighlight ? primaryColor : null),
          ),
        );

        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, const SizedBox(height: 4), valueText],
          );
        }
        return Row(
          children: [
            Expanded(child: labelText),
            const SizedBox(width: 12),
            Expanded(child: valueText),
          ],
        );
      },
    );
  }
}
