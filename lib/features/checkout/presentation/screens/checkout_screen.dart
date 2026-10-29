import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/widgets/app_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/address_model.dart';
import '../providers/checkout_provider.dart';
import 'order_success_screen.dart';
import '../../../../core/utils/gstin.dart';

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
  double _total(dynamic cart) => double.parse(
    (cart.grandTotal - (_withGst ? 0 : cart.gstAmount)).toStringAsFixed(2),
  );
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

  Widget _invoiceDetails() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final borderColor = isDark
        ? const Color(0xFF263548)
        : const Color(0xFFE2E8F0);

    return Form(
      key: _invoiceForm,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GST billing preference',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
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
            ),
            const SizedBox(height: 20),
            Text(
              'Business details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company / business name',
              ),
            ),
            const SizedBox(height: 18),
            if (_withGst) ...[
              TextFormField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'GST Number (required)',
                ),
                validator: (value) => isValidGstin(value ?? '')
                    ? null
                    : 'Enter a valid GST number',
              ),
              const SizedBox(height: 18),
            ],
            TextFormField(
              controller: _pan,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'PAN (optional)'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ||
                      RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
                          .hasMatch(value!.trim().toUpperCase())
                  ? null
                  : 'Enter a valid PAN',
            ),
            const SizedBox(height: 16),
            Divider(color: borderColor, height: 24),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Billing address is the same as delivery'),
                value: _sameAsDelivery,
                onChanged: (value) =>
                    setState(() => _sameAsDelivery = value ?? true),
              ),
            ),
            if (!_sameAsDelivery) ...[
              const SizedBox(height: 12),
              const Text(
                'Billing address',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              for (final entry in _billing.entries) ...[
                TextFormField(
                  controller: entry.value,
                  keyboardType: entry.key == 'mobile' || entry.key == 'pincode'
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: {
                      'name': 'Recipient / business',
                      'mobile': 'Mobile',
                      'address': 'Street address',
                      'city': 'City',
                      'state': 'State',
                      'pincode': 'Pincode',
                    }[entry.key],
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Required';
                    if (entry.key == 'pincode' &&
                        !RegExp(r'^\d{6}$').hasMatch(text)) {
                      return 'Enter a six-digit pincode';
                    }
                    if (entry.key == 'mobile' &&
                        !RegExp(r'^\d{10}$').hasMatch(text)) {
                      return 'Enter a ten-digit mobile number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
              ],
            ],
            const SizedBox(height: 4),
            TextFormField(
              controller: _deliveryNote,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Delivery instructions (optional)',
              ),
            ),
          ],
        ),
      ),
    );
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: orderId,
            withGst: _withGst,
            paymentMethod: paymentMethod,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    final cartState = ref.watch(cartProvider);
    final checkoutState = ref.watch(checkoutProvider);
    final selectedAddress = checkoutState.selectedAddress;

    return Scaffold(
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. DELIVERY ADDRESS SECTION
                    _buildSectionHeader(
                      '1. Delivery & Billing Address',
                      isDark,
                    ),
                    const SizedBox(height: 10),
                    _buildAddressCard(
                      context,
                      ref,
                      selectedAddress,
                      checkoutState.addresses,
                      isDark,
                      primaryColor,
                    ),

                    const SizedBox(height: 24),

                    _buildSectionHeader('Invoice & billing details', isDark),
                    const SizedBox(height: 10),
                    _invoiceDetails(),
                    const SizedBox(height: 24),

                    // 2. ORDER SUMMARY SECTION
                    _buildSectionHeader(
                      '2. Order Items (${cartState.totalItemCount} Pcs)',
                      isDark,
                    ),
                    const SizedBox(height: 10),
                    _buildOrderItemsSummary(
                      cartState.items,
                      isDark,
                      primaryColor,
                    ),

                    const SizedBox(height: 24),

                    // 3. PRICE BREAKDOWN SECTION
                    _buildSectionHeader('3. Payment & Cost Breakdown', isDark),
                    const SizedBox(height: 10),
                    _buildPriceBreakdown(cartState, isDark, primaryColor),

                    const SizedBox(height: 24),

                    // 4. PAYMENT METHOD SELECTION SECTION (UI ONLY)
                    _buildSectionHeader('4. Select Payment Option', isDark),
                    const SizedBox(height: 10),
                    _buildPaymentMethodOptions(
                      context,
                      ref,
                      checkoutState.selectedPaymentMethod,
                      isDark,
                      primaryColor,
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // 5. STICKY BOTTOM BAR (Grand Total & Place Order Button)
            _buildStickyBottomBar(
              context,
              _total(cartState),
              checkoutState.isPlacingOrder || _submitting,
              isDark,
              primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
    );
  }

  // Address Selection Card
  Widget _buildAddressCard(
    BuildContext context,
    WidgetRef ref,
    AddressModel selectedAddress,
    List<AddressModel> allAddresses,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedAddress.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _showAddressSelectorModal(
                  context,
                  ref,
                  allAddresses,
                  isDark,
                  primaryColor,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${selectedAddress.address}, ${selectedAddress.city}, ${selectedAddress.state} - ${selectedAddress.pincode}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mobile: ${selectedAddress.mobile}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  // Order Items Summary
  Widget _buildOrderItemsSummary(List items, bool isDark, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final product = item.product;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 50,
                    height: 50,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(4),
                    child: AppImage(
                      product.displayImageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qty: ${item.quantity} Pcs • ₹${product.dealerPrice.toStringAsFixed(2)} / Unit',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${item.totalPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Price Breakdown Card
  Widget _buildPriceBreakdown(
    dynamic cartState,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          _buildSummaryRow(
            'Subtotal',
            '₹${cartState.subtotal.toStringAsFixed(2)}',
            isDark,
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            'Gold Dealer Discount (10%)',
            '- ₹${cartState.dealerDiscount.toStringAsFixed(2)}',
            isDark,
            isDiscount: true,
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            'GST Input Tax (18%)',
            '+ ₹${(_withGst ? cartState.gstAmount : 0.0).toStringAsFixed(2)}',
            isDark,
          ),
          const SizedBox(height: 6),
          _buildSummaryRow(
            'Delivery / Freight',
            cartState.deliveryFee == 0
                ? 'FREE'
                : '₹${cartState.deliveryFee.toStringAsFixed(2)}',
            isDark,
            isHighlight: cartState.deliveryFee == 0,
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _withGst
                      ? 'Grand Total (With GST)'
                      : 'Grand Total (Without GST)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₹${_total(cartState).toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
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
    const methods = [
      PaymentMethodType.cashOnDelivery,
      PaymentMethodType.razorpay,
    ];
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
                      '₹${grandTotal.toStringAsFixed(2)}',
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
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
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
