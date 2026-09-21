import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/address_model.dart';
import '../providers/checkout_provider.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  Future<void> _handlePlaceOrder() async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final orderId = await ref.read(checkoutProvider.notifier).placeOrder();

    // Clear cart after successful checkout simulation
    cartNotifier.clearCart();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(orderId: orderId),
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
        title: const Text('B2B Wholesale Checkout'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. DELIVERY ADDRESS SECTION
                    _buildSectionHeader('1. Delivery & Billing Address', isDark),
                    const SizedBox(height: 10),
                    _buildAddressCard(context, ref, selectedAddress, checkoutState.addresses, isDark, primaryColor),

                    const SizedBox(height: 24),

                    // 2. ORDER SUMMARY SECTION
                    _buildSectionHeader('2. Order Items (${cartState.totalItemCount} Pcs)', isDark),
                    const SizedBox(height: 10),
                    _buildOrderItemsSummary(cartState.items, isDark, primaryColor),

                    const SizedBox(height: 24),

                    // 3. PRICE BREAKDOWN SECTION
                    _buildSectionHeader('3. Payment & Cost Breakdown', isDark),
                    const SizedBox(height: 10),
                    _buildPriceBreakdown(cartState, isDark, primaryColor),

                    const SizedBox(height: 24),

                    // 4. PAYMENT METHOD SELECTION SECTION (UI ONLY)
                    _buildSectionHeader('4. Select Payment Option', isDark),
                    const SizedBox(height: 10),
                    _buildPaymentMethodOptions(context, ref, checkoutState.selectedPaymentMethod, isDark, primaryColor),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // 5. STICKY BOTTOM BAR (Grand Total & Place Order Button)
            _buildStickyBottomBar(context, cartState.grandTotal, checkoutState.isPlacingOrder, isDark, primaryColor),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_rounded, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    selectedAddress.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: () => _showAddressSelectorModal(context, ref, allAddresses, isDark, primaryColor),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${selectedAddress.address}, ${selectedAddress.city}, ${selectedAddress.state} - ${selectedAddress.pincode}',
            style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
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
                    color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(product.imageUrl, fit: BoxFit.contain),
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
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qty: ${item.quantity} Pcs • ₹${product.dealerPrice.toStringAsFixed(0)} / Unit',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${item.totalPrice.toStringAsFixed(0)}',
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
  Widget _buildPriceBreakdown(dynamic cartState, bool isDark, Color primaryColor) {
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
          _buildSummaryRow('Subtotal', '₹${cartState.subtotal.toStringAsFixed(0)}', isDark),
          const SizedBox(height: 6),
          _buildSummaryRow('Gold Dealer Discount (10%)', '- ₹${cartState.dealerDiscount.toStringAsFixed(0)}', isDark, isDiscount: true),
          const SizedBox(height: 6),
          _buildSummaryRow('GST Input Tax (18%)', '+ ₹${cartState.gstAmount.toStringAsFixed(0)}', isDark),
          const SizedBox(height: 6),
          _buildSummaryRow('Delivery / Freight', cartState.deliveryFee == 0 ? 'FREE' : '₹${cartState.deliveryFee.toStringAsFixed(0)}', isDark, isHighlight: cartState.deliveryFee == 0),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total (Tax Included)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                '₹${cartState.grandTotal.toStringAsFixed(0)}',
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
    final methods = [
      PaymentMethodType.upi,
      PaymentMethodType.card,
      PaymentMethodType.netbanking,
      PaymentMethodType.razorpay,
    ];

    return Column(
      children: methods.map((method) {
        final isSelected = selectedMethod == method;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? primaryColor : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0)),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: ListTile(
            leading: Radio<PaymentMethodType>(
              value: method,
              groupValue: selectedMethod,
              activeColor: primaryColor,
              onChanged: (val) {
                if (val != null) {
                  ref.read(checkoutProvider.notifier).selectPaymentMethod(val);
                }
              },
            ),
            title: Text(
              method.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            subtitle: Text(
              method.subtitle,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            onTap: () {
              ref.read(checkoutProvider.notifier).selectPaymentMethod(method);
            },
          ),
        );
      }).toList(),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Payable Total', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                '₹${grandTotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 48,
            width: 200,
            child: ElevatedButton(
              onPressed: isPlacingOrder ? null : _handlePlaceOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: isPlacingOrder
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Place Order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isDark, {bool isDiscount = false, bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDiscount
                ? const Color(0xFF10B981)
                : (isHighlight ? const Color(0xFF10B981) : (isDark ? Colors.white : const Color(0xFF0F172A))),
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
              const Text('Select Delivery Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...addresses.map((addr) {
                return ListTile(
                  title: Text(addr.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${addr.address}, ${addr.city} (${addr.pincode})', style: const TextStyle(fontSize: 11)),
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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name / Business')),
                TextField(controller: mobileCtrl, decoration: const InputDecoration(labelText: 'Mobile Number')),
                TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
                TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City')),
                TextField(controller: stateCtrl, decoration: const InputDecoration(labelText: 'State')),
                TextField(controller: pincodeCtrl, decoration: const InputDecoration(labelText: 'Pincode')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && addressCtrl.text.isNotEmpty) {
                  final newAddr = AddressModel(
                    id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text,
                    mobile: mobileCtrl.text,
                    address: addressCtrl.text,
                    city: cityCtrl.text,
                    state: stateCtrl.text,
                    pincode: pincodeCtrl.text,
                  );
                  ref.read(checkoutProvider.notifier).addAddress(newAddr);
                  Navigator.pop(context);
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
