import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';

// Shared palette for the orders page.
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6ECF2);
const _page = Color(0xFFF4F7FB);
const _brand = Color(0xFF175CD3);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : _page,
      body: SafeArea(
        child: user == null
            ? _Message(
                icon: Icons.lock_outline_rounded,
                title: 'Sign in to see your orders.',
                actionLabel: 'Sign in',
                onAction: () => context.go('/login'),
              )
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: _orders,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState != ConnectionState.done;
                  final orders = snapshot.data ?? const [];
                  return _Centered(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          count: loading || snapshot.hasError
                              ? null
                              : orders.length,
                          onRefresh: () => setState(_refresh),
                        ),
                        Expanded(child: _body(snapshot, loading, orders)),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _body(
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
    bool loading,
    List<Map<String, dynamic>> orders,
  ) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: '${snapshot.error}',
        actionLabel: 'Retry',
        onAction: () => setState(_refresh),
      );
    }
    if (orders.isEmpty) {
      return _Message(
        icon: Icons.receipt_long_outlined,
        title: 'No wholesale orders yet',
        actionLabel: 'Browse catalog',
        onAction: () => context.go('/products'),
      );
    }

    String statusOf(Map o) => '${o['status'] ?? 'Pending'}';
    final counts = <String, int>{};
    for (final o in orders) {
      counts.update(statusOf(o), (v) => v + 1, ifAbsent: () => 1);
    }
    final filters = ['All', ...counts.keys];
    final shown = _filter == 'All'
        ? orders
        : orders
              .where((o) => statusOf(o).toLowerCase() == _filter.toLowerCase())
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = filters[i];
              return _FilterPill(
                label: f,
                count: f == 'All' ? orders.length : counts[f]!,
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
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
                        child: Text(
                          'No orders with this status',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _OrderCard(order: shown[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Keeps content at a comfortable reading width on large screens.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: child,
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onRefresh});
  final int? count;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My orders',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == null
                      ? 'Track and review your wholesale orders'
                      : '$count ${count == 1 ? 'order' : 'orders'}',
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            onPressed: onRefresh,
            tooltip: 'Refresh orders',
            style: IconButton.styleFrom(
              backgroundColor: isDark ? null : Colors.white,
              side: const BorderSide(color: _line),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? Colors.white : (isDark ? Colors.white70 : _ink);
    return Material(
      color: selected
          ? _brand
          : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
      shape: StadiumBorder(side: BorderSide(color: selected ? _brand : _line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF1FB),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: _brand),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _expanded = false;

  Map<String, dynamic> get order => widget.order;

  /// Image for an order line. Orders often store an empty or generic
  /// placeholder image, so prefer the live catalogue product's display image
  /// (matched by id, then SKU, then name) and fall back to the saved one.
  static String _imageFor(Map item, List<ProductModel> catalog) {
    String field(String key) => '${item[key] ?? ''}'.trim();
    final id = field('id').isNotEmpty ? field('id') : field('productId');
    final sku = field('sku').toUpperCase();
    final name = field('name').toLowerCase();
    ProductModel? match;
    for (final p in catalog) {
      if (id.isNotEmpty && p.id == id) {
        match = p;
        break;
      }
    }
    match ??= catalog
        .where((p) => sku.isNotEmpty && p.sku.toUpperCase() == sku)
        .firstOrNull;
    match ??= catalog
        .where((p) => name.isNotEmpty && p.name.toLowerCase() == name)
        .firstOrNull;
    if (match != null && match.displayImageUrl.trim().isNotEmpty) {
      return match.displayImageUrl;
    }
    return field('imgSrc').isNotEmpty ? field('imgSrc') : field('image');
  }

  static Widget _thumb(String source, double size) {
    const fallback = Icon(
      Icons.inventory_2_outlined,
      color: Colors.blueGrey,
      size: 22,
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _page,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: source.isEmpty
          ? fallback
          : AppImage(
              source,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }

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

  static Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('partial')) return const Color(0xFFB54708);
    if (value.contains('deliver') || value == 'completed') {
      return const Color(0xFF16834A);
    }
    if (value.contains('cancel')) return const Color(0xFFB42318);
    return _brand;
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// 1234567.5 -> 12,34,567.50 (Indian digit grouping).
  static String _money(num value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    var whole = parts[0];
    final negative = whole.startsWith('-');
    if (negative) whole = whole.substring(1);
    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      var rest = whole.substring(0, whole.length - 3);
      final groups = <String>[];
      while (rest.length > 2) {
        groups.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) groups.insert(0, rest);
      whole = '${groups.join(',')},$last3';
    }
    return '${negative ? '-' : ''}₹$whole.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catalog =
        ref.watch(catalogProductsProvider).valueOrNull ??
        const <ProductModel>[];
    final items = (order['items'] as List? ?? []).whereType<Map>().toList();
    final amount = num.tryParse('${order['grandTotal'] ?? 0}') ?? 0;
    final date = DateTime.tryParse('${order['createdAt'] ?? ''}');
    final dateText = date == null
        ? 'Date unavailable'
        : '${date.day} ${_months[date.month - 1]} ${date.year}';
    final status = '${order['status'] ?? 'Pending'}';
    final statusColor = _statusColor(status);
    final imageSource = items.isEmpty ? '' : _imageFor(items.first, catalog);
    final summary = items.isEmpty
        ? 'No items'
        : '${items.first['name'] ?? 'Product'}'
              '${items.length > 1 ? '  +${items.length - 1} more' : ''}';
    final ink = isDark ? Colors.white : _ink;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132233) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded ? _brand.withValues(alpha: 0.35) : _line,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2850).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _thumb(imageSource, 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${_shortOrderId(order['orderId'])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusPill(status, statusColor),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: _muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateText,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money(amount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                        const SizedBox(height: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? _details(catalog, items, ink)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(List<ProductModel> catalog, List<Map> items, Color ink) {
    final delivery = _addressText(order['deliveryAddress']);
    final billing = _addressText(order['billingAddress']);
    String text(String key) => '${order[key] ?? ''}'.trim();

    final facts = <(String, String)>[
      (
        'Payment method',
        text('paymentMethod').isEmpty ? '—' : text('paymentMethod'),
      ),
      if (order['invoiceNumber'] != null)
        ('Invoice', '${order['invoiceNumber']}'),
      if (text('gstin').isNotEmpty) ('GSTIN', text('gstin')),
      if (text('companyName').isNotEmpty) ('Company', text('companyName')),
      if (text('panNumber').isNotEmpty) ('PAN', text('panNumber')),
    ];
    final billingText = billing.isNotEmpty
        ? billing
        : (order['sameAsDelivery'] == true && delivery.isNotEmpty
              ? 'Same as delivery address'
              : '');

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Items'),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _thumb(_imageFor(item, catalog), 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['name'] ?? 'Product'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            'Qty ${item['quantity'] ?? 1}',
                            if ('${item['sku'] ?? ''}'.isNotEmpty)
                              '${item['sku']}',
                          ].join('  ·  '),
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _money(
                      num.tryParse(
                            '${item['numericPrice'] ?? item['price'] ?? 0}',
                          ) ??
                          0,
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const _SectionLabel('Details'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final f in facts) _FactTile(f.$1, f.$2)],
          ),
          if (delivery.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AddressTile(
              icon: Icons.local_shipping_outlined,
              label: 'Delivery address',
              value: delivery,
            ),
          ],
          if (billingText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AddressTile(
              icon: Icons.receipt_long_outlined,
              label: 'Billing address',
              value: billingText,
            ),
          ],
          if (text('deliveryNote').isNotEmpty) ...[
            const SizedBox(height: 10),
            _AddressTile(
              icon: Icons.sticky_note_2_outlined,
              label: 'Delivery note',
              value: text('deliveryNote'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status, this.color);
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: _muted,
      ),
    ),
  );
}

class _FactTile extends StatelessWidget {
  const _FactTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : _page,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : _ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : _page,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
