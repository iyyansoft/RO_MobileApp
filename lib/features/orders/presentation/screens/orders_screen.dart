import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  late Future<List<Map<String, dynamic>>> _orders;
  String? _loadedIdentity;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final user = ref.read(authProvider).currentUser;
    _loadedIdentity = '${user?.id}|${user?.email}';
    _orders = _loadOrders(user?.id ?? '', user?.email ?? '');
  }

  Future<List<Map<String, dynamic>>> _loadOrders(
    String userId,
    String email,
  ) async {
    if (email.isEmpty) return [];
    if (SupabaseConfig.dealerDataSessionActive) {
      return const SupabaseDealerDataRepository().loadOrders(userId, email);
    }
    final response = await ApiClient().get<Map<String, dynamic>>(
      'user/orders',
      queryParameters: {'email': email},
    );
    final data = response.data ?? {};
    if (data['success'] != true) {
      throw ApiException(
        message: '${data['error'] ?? 'Could not load orders.'}',
      );
    }
    return (data['orders'] as List? ?? [])
        .whereType<Map>()
        .map((order) => Map<String, dynamic>.from(order))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    if (_loadedIdentity != '${user?.id}|${user?.email}') {
      _filter = 'All';
      _refresh();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My orders'),
        actions: [
          IconButton(
            onPressed: () => setState(_refresh),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh orders',
          ),
        ],
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sign in to see your orders.'),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            )
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _orders,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${snapshot.error}', textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => setState(_refresh),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 56),
                        const SizedBox(height: 12),
                        const Text('No wholesale orders yet'),
                        TextButton(
                          onPressed: () => context.go('/products'),
                          child: const Text('Browse catalog'),
                        ),
                      ],
                    ),
                  );
                }
                final filters = <String>[
                  'All',
                  ...orders
                      .map((order) => '${order['status'] ?? 'Pending'}')
                      .toSet(),
                ];
                final shown = _filter == 'All'
                    ? orders
                    : orders
                          .where(
                            (o) =>
                                '${o['status'] ?? 'Pending'}'.toLowerCase() ==
                                _filter.toLowerCase(),
                          )
                          .toList();
                return Column(
                  children: [
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: filters
                            .map(
                              (filter) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(filter),
                                  selected: _filter == filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          setState(_refresh);
                          await _orders;
                        },
                        child: shown.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 100),
                                  Center(
                                    child: Text('No orders with this status'),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  12,
                                ),
                                itemCount: shown.length,
                                itemBuilder: (context, index) =>
                                    _OrderCard(order: shown[index]),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;

  String _addressText(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      if (value.trim().isEmpty) return '';
      try {
        return _addressText(jsonDecode(value));
      } on FormatException {
        return value;
      }
    }
    if (value is Map) {
      const keys = [
        'name',
        'fullName',
        'businessName',
        'doorNo',
        'address',
        'street',
        'area',
        'city',
        'district',
        'state',
        'pincode',
        'mobile',
        'phone',
      ];
      return keys
          .map((key) => '${value[key] ?? ''}'.trim())
          .where((part) => part.isNotEmpty)
          .join(', ');
    }
    return '$value';
  }

  String _shortOrderId(dynamic value) {
    final id = '${value ?? ''}'.trim();
    if (id.isEmpty) return 'RO-';
    final idWithoutPrefix = id.toLowerCase().startsWith('ro-')
        ? id.substring(3)
        : id;
    final shortId = idWithoutPrefix.length > 8
        ? idWithoutPrefix.substring(0, 8)
        : idWithoutPrefix;
    return 'RO-$shortId';
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('partial')) return const Color(0xFFB54708);
    if (value.contains('deliver') || value == 'completed') {
      return const Color(0xFF16834A);
    }
    if (value.contains('cancel')) return const Color(0xFFB42318);
    return const Color(0xFF175CD3);
  }

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List? ?? []).whereType<Map>().toList();
    final amount = (num.tryParse('${order['grandTotal'] ?? 0}') ?? 0)
        .toStringAsFixed(2);
    final date = DateTime.tryParse('${order['createdAt'] ?? ''}');
    final dateText = date == null
        ? ''
        : '${date.day}/${date.month}/${date.year}';
    final status = '${order['status'] ?? 'Pending'}';
    final imageSource = items.isEmpty
        ? ''
        : '${items.first['imgSrc'] ?? items.first['image'] ?? ''}';
    final delivery = _addressText(order['deliveryAddress']);
    final billing = _addressText(order['billingAddress']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            color: const Color(0xFFF1F6FC),
            alignment: Alignment.center,
            child: imageSource.trim().isEmpty
                ? const Icon(Icons.inventory_2_outlined, color: Colors.blueGrey)
                : AppImage(
                    imageSource,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.blueGrey,
                    ),
                  ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Order #${_shortOrderId(order['orderId'])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '\u20B9$amount',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  dateText.isEmpty ? 'Date unavailable' : dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        children: [
          for (final item in items)
            ListTile(
              title: Text('${item['name'] ?? 'Product'}'),
              subtitle: Text(
                'Qty ${item['quantity'] ?? 1}  •  ${item['sku'] ?? ''}',
              ),
              trailing: Text('₹${item['numericPrice'] ?? item['price'] ?? 0}'),
            ),
          if (order['invoiceNumber'] != null)
            ListTile(
              title: const Text('Invoice'),
              subtitle: Text('${order['invoiceNumber']}'),
            ),
          ListTile(
            title: const Text('Payment method'),
            subtitle: Text('${order['paymentMethod'] ?? '—'}'),
          ),
          if (delivery.isNotEmpty)
            ListTile(
              title: const Text('Delivery address'),
              subtitle: Text(delivery),
            ),
          if (billing.isNotEmpty)
            ListTile(
              title: const Text('Billing address'),
              subtitle: Text(billing),
            ),
          if (billing.isEmpty &&
              order['sameAsDelivery'] == true &&
              delivery.isNotEmpty)
            const ListTile(
              title: Text('Billing address'),
              subtitle: Text('Same as delivery address'),
            ),
          if ('${order['deliveryNote'] ?? ''}'.trim().isNotEmpty)
            ListTile(
              title: const Text('Delivery note'),
              subtitle: Text('${order['deliveryNote']}'),
            ),
          if ('${order['gstin'] ?? ''}'.trim().isNotEmpty)
            ListTile(
              title: const Text('GSTIN'),
              subtitle: Text('${order['gstin']}'),
            ),
          if ('${order['companyName'] ?? ''}'.trim().isNotEmpty)
            ListTile(
              title: const Text('Company'),
              subtitle: Text('${order['companyName']}'),
            ),
          if ('${order['panNumber'] ?? ''}'.trim().isNotEmpty)
            ListTile(
              title: const Text('PAN'),
              subtitle: Text('${order['panNumber']}'),
            ),
        ],
      ),
    );
  }
}
