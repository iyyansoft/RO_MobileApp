import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/widgets/app_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../cart/domain/order_pricing.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/address_model.dart';
import '../providers/checkout_provider.dart';
import '../../../products/presentation/widgets/max_quantity_dialog.dart';
import 'order_success_screen.dart';
import '../../../../core/utils/gstin.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../products/presentation/widgets/cart_actions.dart'
    show cartErrorText;

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _invoiceForm = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _deliveryNote = TextEditingController();
  final _billing = <String, TextEditingController>{
    for (final key in ['name', 'mobile', 'address', 'city', 'state', 'pincode'])
      key: TextEditingController(),
  };
  bool _sameAsDelivery = true;
  bool _withGst = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).currentUser;
    _company.text = user?.companyName ?? '';
    _gstin.text = user?.gstNumber ?? '';
  }

  @override
  void dispose() {
    for (final controller in [
      _company,
      _gstin,
      _pan,
      _deliveryNote,
      ..._billing.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _gstOption({
    required double width,
    required String title,
    required String subtitle,
    required bool selected,
    required Color primaryColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: Material(
        color: selected
            ? primaryColor.withValues(alpha: isDark ? 0.18 : 0.07)
            : (isDark ? const Color(0xFF172435) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? primaryColor : borderColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected
                      ? primaryColor
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlaceOrder() async {
    if (_submitting || !(_invoiceForm.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _submitting = true);
    final cartNotifier = ref.read(cartProvider.notifier);
    final paymentMethod = ref.read(checkoutProvider).selectedPaymentMethod;
    String orderId;
    try {
      orderId = await ref
          .read(checkoutProvider.notifier)
          .placeOrder(
            withGst: _withGst,
            companyName: _company.text.trim(),
            gstin: _gstin.text.trim().toUpperCase(),
            panNumber: _pan.text.trim().toUpperCase(),
            deliveryNote: _deliveryNote.text.trim(),
            sameAsDelivery: _sameAsDelivery,
            billingAddress: _sameAsDelivery
                ? null
                : {
                    for (final entry in _billing.entries)
                      entry.key: entry.value.text.trim(),
                  },
          );
    } catch (e) {
      // Checkout re-validates the product maximum: the same popup.
      if (mounted && !showMaxQuantityDialogFor(context, e)) {
        AppToast.error(context, cartErrorText(e));
      }
      if (mounted) setState(() => _submitting = false);
      return;
    }

    // Clear the persisted cart only after the order has been saved.
    try {
      await cartNotifier.clearCart();
    } catch (_) {
      await cartNotifier.refreshCart();
    }

    if (mounted) {
      // A real route (not an imperative push) so the success screen's
      // "Track Order Status" / "Back to Home" buttons navigate normally and
      // the page survives a browser refresh.
      context.go(
        OrderSuccessScreen.location(
          orderId: orderId,
          withGst: _withGst,
          paymentMethod: paymentMethod,
        ),
      );
    }
  }

  // ---- Layout helpers ---------------------------------------------------------
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  Color _border(bool isDark) =>
      isDark ? const Color(0xFF263548) : const Color(0xFFE2E8F0);

  /// White card with a light border and subtle shadow.
  BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
    color: isDark ? AppColors.surfaceDark : Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: _border(isDark)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF0F2850).withValues(alpha: isDark ? 0.18 : 0.05),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );

  /// A numbered checkout section card with a clear heading.
  Widget _sectionCard({
    required int step,
    required String title,
    required Widget child,
    required bool isDark,
    required Color primaryColor,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  /// Compact, consistent form fields for the checkout forms.
  ThemeData _formTheme(ThemeData base, bool isDark, Color primaryColor) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF14212F) : const Color(0xFFFBFCFE),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: border(_border(isDark)),
        enabledBorder: border(_border(isDark)),
        focusedBorder: border(primaryColor, 1.6),
        errorBorder: border(const Color(0xFFDC2626)),
        focusedErrorBorder: border(const Color(0xFFDC2626), 1.6),
        labelStyle: const TextStyle(fontSize: 13.5),
      ),
    );
  }

  // ---- Left column sections ------------------------------------------------------

  Widget _gstPreferenceSection(bool isDark, Color primaryColor) {
    final borderColor = _border(isDark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;
        final optionWidth = isCompact
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _gstOption(
              width: optionWidth,
              title: 'With GST',
              subtitle: 'Include GST details',
              selected: _withGst,
              primaryColor: primaryColor,
              borderColor: borderColor,
              onTap: () => setState(() => _withGst = true),
            ),
            _gstOption(
              width: optionWidth,
              title: 'Without GST',
              subtitle: 'Continue without GST',
              selected: !_withGst,
              primaryColor: primaryColor,
              borderColor: borderColor,
              onTap: () => setState(() => _withGst = false),
            ),
          ],
        );
      },
    );
  }

  Widget _businessSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final two = constraints.maxWidth >= 560;
        final gstin = TextFormField(
          controller: _gstin,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'GST Number (required)'),
          validator: (value) =>
              isValidGstin(value ?? '') ? null : 'Enter a valid GST number',
        );
        final pan = TextFormField(
          controller: _pan,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'PAN (optional)'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ||
                  RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
                      .hasMatch(value!.trim().toUpperCase())
              ? null
              : 'Enter a valid PAN',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company / business name',
              ),
            ),
            const SizedBox(height: 14),
            if (_withGst && two)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: gstin),
                  const SizedBox(width: 12),
                  Expanded(child: pan),
                ],
              )
            else ...[
              if (_withGst) ...[gstin, const SizedBox(height: 14)],
              pan,
            ],
          ],
        );
      },
    );
  }

  Widget _billingSection(bool isDark) {
    const labels = {
      'name': 'Recipient / business',
      'mobile': 'Mobile',
      'address': 'Street address',
      'city': 'City',
      'state': 'State',
      'pincode': 'Pincode',
    };
    Widget field(String key) => TextFormField(
      controller: _billing[key],
      keyboardType: key == 'mobile' || key == 'pincode'
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(labelText: labels[key]),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return 'Required';
        if (key == 'pincode' && !RegExp(r'^\d{6}$').hasMatch(text)) {
          return 'Enter a six-digit pincode';
        }
        if (key == 'mobile' && !RegExp(r'^\d{10}$').hasMatch(text)) {
          return 'Enter a ten-digit mobile number';
        }
        return null;
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final two = constraints.maxWidth >= 560;
        Widget pair(String a, String b) => two
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field(a)),
                  const SizedBox(width: 12),
                  Expanded(child: field(b)),
                ],
              )
            : Column(
                children: [field(a), const SizedBox(height: 14), field(b)],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Billing address is the same as delivery',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                value: _sameAsDelivery,
                onChanged: (value) =>
                    setState(() => _sameAsDelivery = value ?? true),
              ),
            ),
            if (!_sameAsDelivery) ...[
              const SizedBox(height: 10),
              pair('name', 'mobile'),
              const SizedBox(height: 14),
              field('address'),
              const SizedBox(height: 14),
              pair('city', 'state'),
              const SizedBox(height: 14),
              field('pincode'),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _deliveryNote,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Delivery instructions (optional)',
              ),
            ),
          ],
        );
      },
    );
  }

  /// All checkout forms, one Form so Place Order validates everything.
  Widget _checkoutForms(
    BuildContext context,
    CheckoutState checkoutState,
    bool isDark,
    Color primaryColor,
  ) {
    final selectedAddress = checkoutState.selectedAddress;
    return Theme(
      data: _formTheme(Theme.of(context), isDark, primaryColor),
      child: Form(
        key: _invoiceForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionCard(
              step: 1,
              title: 'Delivery Address',
              isDark: isDark,
              primaryColor: primaryColor,
              trailing: OutlinedButton.icon(
                onPressed: () => _showAddressSelectorModal(
                  context,
                  ref,
                  checkoutState.addresses,
                  isDark,
                  primaryColor,
                ),
                icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                label: const Text('Change Address'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              child: _buildAddressDetails(
                selectedAddress,
                isDark,
                primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              step: 2,
              title: 'GST Billing Preference',
              isDark: isDark,
              primaryColor: primaryColor,
              child: _gstPreferenceSection(isDark, primaryColor),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              step: 3,
              title: 'Business Details',
              isDark: isDark,
              primaryColor: primaryColor,
              child: _businessSection(),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              step: 4,
              title: 'Invoice & Billing Details',
              isDark: isDark,
              primaryColor: primaryColor,
              child: _billingSection(isDark),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              step: 5,
              title: 'Payment Method',
              isDark: isDark,
              primaryColor: primaryColor,
              child: _buildPaymentMethodOptions(
                context,
                ref,
                checkoutState.selectedPaymentMethod,
                isDark,
                primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    final cartState = ref.watch(cartProvider);
    // Live totals for the selected GST option (same rules the server uses).
    final totals = ref.watch(cartTotalsProvider(_withGst));
    final checkoutState = ref.watch(checkoutProvider);
    final placing = checkoutState.isPlacingOrder || _submitting;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: const Text(
          'B2B Wholesale Checkout',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final forms = _checkoutForms(
              context,
              checkoutState,
              isDark,
              primaryColor,
            );

            if (constraints.maxWidth >= 1024) {
              // Desktop: forms (65%) | sticky Order Summary (35%). Each
              // column scrolls on its own, so the summary stays in view.
              return ResponsiveContentWrapper(
                maxWidth: 1400,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 65,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: forms,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 35,
                      child: SingleChildScrollView(
                        key: const ValueKey('checkout-order-summary'),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: _buildOrderSummaryCard(
                          cartState,
                          totals,
                          isDark,
                          primaryColor,
                          placeOrderButton: _placeOrderButton(
                            placing,
                            primaryColor,
                            height: 52,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Tablet / mobile: one column, summary below the forms, and the
            // Payable Total + Place Order bar fixed at the bottom.
            return ResponsiveContentWrapper(
              maxWidth: 820,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          forms,
                          const SizedBox(height: 16),
                          _buildOrderSummaryCard(
                            cartState,
                            totals,
                            isDark,
                            primaryColor,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  _buildStickyBottomBar(
                    context,
                    totals.grandTotal,
                    placing,
                    isDark,
                    primaryColor,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Delivery address details (name, address, mobile).
  Widget _buildAddressDetails(
    AddressModel selectedAddress,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: isDark ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_rounded, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedAddress.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${selectedAddress.address}, ${selectedAddress.city}, ${selectedAddress.state} - ${selectedAddress.pincode}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mobile: ${selectedAddress.mobile}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Order Summary: items, price breakdown, payable total and (desktop)
  /// the Place Order button.
  Widget _buildOrderSummaryCard(
    CartState cartState,
    OrderTotals totals,
    bool isDark,
    Color primaryColor, {
    Widget? placeOrderButton,
  }) {
    final items = cartState.items;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Order Summary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${cartState.totalItemCount} Pcs',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 18, color: _border(isDark)),
            _summaryItem(items[i], isDark),
          ],
          Divider(height: 28, color: _border(isDark)),
          _buildPriceBreakdown(totals, isDark, primaryColor),
          if (placeOrderButton != null) ...[
            const SizedBox(height: 18),
            placeOrderButton,
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: _muted),
                SizedBox(width: 5),
                Text(
                  'Secure checkout',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(dynamic item, bool isDark) {
    final product = item.product;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border(isDark)),
          ),
          child: AppImage(product.displayImageUrl, fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: isDark ? Colors.white : _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'SKU: ${product.sku}',
                style: const TextStyle(fontSize: 11.5, color: _muted),
              ),
              Text(
                item.isBulk
                    ? 'Qty: ${item.quantity} Pcs • Bulk ${formatInr(item.unitPrice)} / piece'
                    : 'Qty: ${item.quantity} Pcs • ${formatInr(product.dealerPrice)} / Unit',
                style: const TextStyle(fontSize: 11.5, color: _muted),
              ),
              if (item.isBulk)
                Text(
                  'BULK ORDER • ${product.bulkPackLabel ?? ''}',
                  key: ValueKey('checkout-bulk-${product.id}'),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B5FC4),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatInr(item.totalPrice),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : _ink,
          ),
        ),
      ],
    );
  }

  /// Place Order (validates the forms, then places the order).
  Widget _placeOrderButton(
    bool isPlacingOrder,
    Color primaryColor, {
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isPlacingOrder || ref.watch(cartProvider).items.isEmpty
            ? null
            : _handlePlaceOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isPlacingOrder
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Place Order',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
      ),
    );
  }

  // Price Breakdown (inside the Order Summary)
  Widget _buildPriceBreakdown(
    OrderTotals totals,
    bool isDark,
    Color primaryColor,
  ) {
    return Column(
      children: [
        _buildSummaryRow(
          'Subtotal (${totals.itemCount} Pcs)',
          formatInr(totals.subtotal),
          isDark,
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          discountLabel(
            totals.rules,
            hasBulk: ref.watch(cartProvider).items.any((i) => i.isBulk),
          ),
          '- ${formatInr(totals.discount)}',
          isDark,
          isDiscount: true,
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          _withGst
              ? 'GST (${formatPercent(totals.rules.gstPercent)}% on ${formatInr(totals.taxableAmount)})'
              : 'GST (Without GST)',
          '+ ${formatInr(totals.gst)}',
          isDark,
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(
          'Delivery / Freight',
          totals.freeDelivery ? 'FREE' : formatInr(totals.deliveryFee),
          isDark,
          isHighlight: totals.freeDelivery,
        ),
        Divider(height: 26, color: _border(isDark)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _withGst
                        ? 'Grand Total (With GST)'
                        : 'Grand Total (Without GST)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Final payable amount',
                    style: TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatInr(totals.grandTotal),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Payment Options UI
  Widget _buildPaymentMethodOptions(
    BuildContext context,
    WidgetRef ref,
    PaymentMethodType selectedMethod,
    bool isDark,
    Color primaryColor,
  ) {
    // Razorpay is hidden for now (owner's choice); its payment code is kept so
    // it can be shown again by adding PaymentMethodType.razorpay here.
    const methods = [PaymentMethodType.cashOnDelivery];
    const razorpayBlue = Color(0xFF3478D4);

    return RadioGroup<PaymentMethodType>(
      groupValue: selectedMethod,
      onChanged: (method) {
        if (method != null) {
          ref.read(checkoutProvider.notifier).selectPaymentMethod(method);
        }
      },
      child: Column(
        children: methods.map((method) {
          final isSelected = selectedMethod == method;
          final methodColor = method == PaymentMethodType.razorpay
              ? razorpayBlue
              : primaryColor;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? methodColor
                    : (method == PaymentMethodType.razorpay
                          ? razorpayBlue.withValues(alpha: 0.45)
                          : (isDark
                                ? const Color(0xFF1E2D3D)
                                : const Color(0xFFE2E8F0))),
                width: isSelected
                    ? 2.0
                    : (method == PaymentMethodType.razorpay ? 1.5 : 1.0),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref
                    .read(checkoutProvider.notifier)
                    .selectPaymentMethod(method),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Radio<PaymentMethodType>(
                        value: method,
                        activeColor: methodColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: methodColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          method == PaymentMethodType.razorpay
                              ? Icons.account_balance_wallet_rounded
                              : Icons.local_shipping_rounded,
                          color: methodColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              method.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              method.subtitle,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Sticky Bottom Checkout Action
  Widget _buildStickyBottomBar(
    BuildContext context,
    double grandTotal,
    bool isPlacingOrder,
    bool isDark,
    Color primaryColor,
  ) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Payable Total',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatInr(grandTotal),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      isPlacingOrder || ref.watch(cartProvider).items.isEmpty
                      ? null
                      : _handlePlaceOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isPlacingOrder
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Place Order',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    bool isDark, {
    bool isDiscount = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDiscount
                ? const Color(0xFF10B981)
                : (isHighlight
                      ? AppColors.primaryLight
                      : (isDark ? Colors.white : const Color(0xFF0F172A))),
          ),
        ),
      ],
    );
  }

  void _showAddressSelectorModal(
    BuildContext context,
    WidgetRef ref,
    List<AddressModel> addresses,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Delivery Address',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...addresses.map((addr) {
                return ListTile(
                  title: Text(
                    addr.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${addr.address}, ${addr.city} (${addr.pincode})',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Icon(Icons.check_circle, color: primaryColor),
                  onTap: () {
                    ref.read(checkoutProvider.notifier).selectAddress(addr.id);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddAddressDialog(context, ref, isDark);
                  },
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Add New Delivery Address'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddAddressDialog(BuildContext context, WidgetRef ref, bool isDark) {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final stateCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Delivery Address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name / Business',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: mobileCtrl,
                  decoration: const InputDecoration(labelText: 'Mobile Number'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: stateCtrl,
                  decoration: const InputDecoration(labelText: 'State'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pincodeCtrl,
                  decoration: const InputDecoration(labelText: 'Pincode'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty &&
                    mobileCtrl.text.trim().isNotEmpty &&
                    addressCtrl.text.trim().isNotEmpty &&
                    cityCtrl.text.trim().isNotEmpty &&
                    stateCtrl.text.trim().isNotEmpty &&
                    RegExp(r'^\d{6}$').hasMatch(pincodeCtrl.text.trim())) {
                  final newAddr = AddressModel(
                    id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text,
                    mobile: mobileCtrl.text,
                    address: addressCtrl.text,
                    city: cityCtrl.text,
                    state: stateCtrl.text,
                    pincode: pincodeCtrl.text,
                  );
                  try {
                    await ref
                        .read(checkoutProvider.notifier)
                        .addAddress(newAddr);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      AppToast.error(context, cartErrorText(e));
                    }
                  }
                }
              },
              child: const Text('Save Address'),
            ),
          ],
        );
      },
    );
  }
}
