import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/order_id.dart';
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

  /// Route for this screen. Order details travel in the query string so a
  /// browser refresh or a shared link still shows the confirmation.
  static const path = '/order-success';

  static String location({
    required String orderId,
    required bool withGst,
    required PaymentMethodType paymentMethod,
  }) => Uri(
    path: path,
    queryParameters: {
      'id': orderId,
      if (withGst) 'gst': '1',
      'pay': paymentMethod.name,
    },
  ).toString();

  /// Builds the screen from a route's query parameters, or returns null if
  /// the order id is missing.
  static OrderSuccessScreen? fromQuery(Map<String, String> query) {
    final id = query['id'];
    if (id == null || id.isEmpty) return null;
    final pay = PaymentMethodType.values.where((m) => m.name == query['pay']);
    return OrderSuccessScreen(
      orderId: id,
      withGst: query['gst'] == '1',
      paymentMethod: pay.isEmpty ? PaymentMethodType.cashOnDelivery : pay.first,
    );
  }

  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final displayId = formatOrderId(orderId);
    final isPaid = paymentMethod != PaymentMethodType.cashOnDelivery;

    final pageBg = isDark ? AppColors.backgroundDark : const Color(0xFFF4F7FB);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE6ECF2);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    padding: constraints.maxWidth < 400
                        ? const EdgeInsets.fromLTRB(16, 28, 16, 18)
                        : const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F2850)
                              .withValues(alpha: isDark ? 0.3 : 0.06),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SuccessBadge(),
                        const SizedBox(height: 20),
                        Text(
                          'B2B Wholesale Order Placed!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your order has been saved. View your orders to check its status and invoice.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: muted,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _OrderIdChip(
                          displayId: displayId,
                          color: primaryColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 22),

                        // Details
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: border),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              _DetailRow(
                                icon: Icons.schedule_rounded,
                                label: 'Estimated Dispatch',
                                value: const Text('Express (Within 24 Hours)'),
                                muted: muted,
                              ),
                              _divider(border),
                              _DetailRow(
                                icon: Icons.receipt_long_rounded,
                                label: 'GST Invoice Status',
                                value: _Pill(
                                  withGst
                                      ? 'GST Invoice Generated'
                                      : 'Without GST',
                                  color: _green,
                                ),
                                muted: muted,
                              ),
                              _divider(border),
                              _DetailRow(
                                icon: Icons.account_balance_wallet_rounded,
                                label: 'Payment Method',
                                value: Text(paymentMethod.label),
                                muted: muted,
                              ),
                              _divider(border),
                              _DetailRow(
                                icon: Icons.verified_rounded,
                                label: 'Payment Status',
                                value: _Pill(
                                  isPaid ? 'Paid' : 'Due on Delivery',
                                  color: isPaid ? _green : _amber,
                                ),
                                muted: muted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Actions
                        LayoutBuilder(
                          builder: (context, c) {
                            final track = SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: () => context.go('/orders'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                // Own Row so the label can shrink on narrow
                                // widths instead of overflowing.
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_shipping_rounded,
                                      size: 19,
                                    ),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Track Order Status',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            final home = SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => context.go('/home'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: titleColor,
                                  side: BorderSide(color: border, width: 1.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Back to Home',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                            if (c.maxWidth < 380) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  track,
                                  const SizedBox(height: 10),
                                  home,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(flex: 5, child: home),
                                const SizedBox(width: 12),
                                Expanded(flex: 6, child: track),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _divider(Color color) =>
      Divider(height: 1, thickness: 1, color: color.withValues(alpha: 0.7));
}

/// Green tick in soft rings that pops in once.
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    const green = OrderSuccessScreen._green;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: green.withValues(alpha: 0.08),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: green,
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

class _OrderIdChip extends StatelessWidget {
  const _OrderIdChip({
    required this.displayId,
    required this.color,
    required this.isDark,
  });

  final String displayId;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.07),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Order ID',
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Copy order ID',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: color,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: displayId));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Order ID copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 17, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
