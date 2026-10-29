import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../products/domain/models/product_model.dart';
import '../data/shop_employee_repository.dart';
import '../data/shop_orders_preview.dart';

const _shopOrdersPreviewEnabled = bool.fromEnvironment('SHOP_ORDERS_PREVIEW');
const _ink = Color(0xFF17345B);
const _muted = Color(0xFF71839D);

class ShopEmployeeLoginScreen extends StatefulWidget {
  const ShopEmployeeLoginScreen({super.key});
  @override
  State<ShopEmployeeLoginScreen> createState() =>
      _ShopEmployeeLoginScreenState();
}

class _ShopEmployeeLoginScreenState extends State<ShopEmployeeLoginScreen> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  final _repo = ShopEmployeeRepository.instance;
  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_id.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your Employee ID and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.login(_id.text, _password.text);
      if (mounted) context.go('/shop/app');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPasswordHelp() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Forgot password?'),
      content: const Text(
        'Shop employee passwords are managed by your administrator. Contact your shop admin to reset your Login ID password.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFFE5ECF5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(width: 250, height: 90)),
                  const SizedBox(height: 22),
                  const Text(
                    'Shop Employee Login',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in with the Login ID and password provided by your administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _id,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Employee ID / Login ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showPasswordHelp,
                      child: const Text('Forgot Password?'),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ShopAppScreen extends StatefulWidget {
  const ShopAppScreen({super.key});
  @override
  State<ShopAppScreen> createState() => _ShopAppScreenState();
}

class _ShopAppScreenState extends State<ShopAppScreen> {
  final _repo = ShopEmployeeRepository.instance;
  final _ordersKey = GlobalKey<_ShopOrdersScreenState>();
  final _deliveriesKey = GlobalKey<_ShopOrdersScreenState>();
  int _tab = 1;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await _repo.restore();
    if (!mounted) return;
    if (_repo.token == null) {
      context.go('/shop/login');
      return;
    }
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [
      ShopDashboard(repo: _repo),
      ShopOrdersScreen(
        key: _ordersKey,
        repo: _repo,
        onNewEnquiry: () => setState(() => _tab = 5),
      ),
      ShopOrdersScreen(
        key: _deliveriesKey,
        repo: _repo,
        deliveriesOnly: true,
        onNewEnquiry: () => setState(() => _tab = 5),
      ),
      ShopVendorsScreen(repo: _repo),
      ShopProductsScreen(repo: _repo),
      ShopEnquiryScreen(repo: _repo),
      ShopReportsScreen(repo: _repo),
      ShopEmployeeProfileScreen(repo: _repo),
    ];
    const destinations = [
      ('Overview', Icons.space_dashboard_outlined),
      ('Current Orders', Icons.receipt_long_outlined),
      ('Deliveries', Icons.local_shipping_outlined),
      ('Vendors', Icons.people_alt_outlined),
      ('Products', Icons.inventory_2_outlined),
      ('New Enquiries', Icons.add_business_outlined),
      ('Sales Reports', Icons.query_stats_outlined),
      ('Profile', Icons.person_outline_rounded),
    ];
    const bottomDestinations = <(String, IconData, int)>[
      ('Current Orders', Icons.receipt_long_outlined, 1),
      ('Products', Icons.inventory_2_outlined, 4),
      ('Enquiries', Icons.add_business_outlined, 5),
      ('Profile', Icons.person_outline_rounded, 7),
    ];
    final bottomSelection = bottomDestinations.indexWhere(
      (destination) => destination.$3 == _tab,
    );
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(destinations[_tab].$1),
        actions: [
          if (_tab == 1 || _tab == 2)
            IconButton(
              tooltip: _tab == 1 ? 'Refresh orders' : 'Refresh',
              onPressed: () {
                if (_tab == 1) _ordersKey.currentState?.refresh();
                if (_tab == 2) _deliveriesKey.currentState?.refresh();
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: bottomSelection < 0 ? 0 : bottomSelection,
        onDestinationSelected: (index) {
          final destination = bottomDestinations[index];
          setState(() => _tab = destination.$3);
        },
        destinations: [
          for (final destination in bottomDestinations)
            NavigationDestination(
              icon: Icon(destination.$2),
              label: destination.$1,
            ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          setState(() => _tab = index);
        },
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandLogo(width: 160, height: 58),
                SizedBox(height: 8),
                Text(
                  'SHOP APP',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < destinations.length; index++)
            NavigationDrawerDestination(
              icon: Icon(destinations[index].$2),
              label: Text(destinations[index].$1),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 24),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: () async {
              Navigator.of(context).pop();
              await _repo.logout();
              if (!context.mounted) return;
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class ShopEmployeeProfileScreen extends StatelessWidget {
  const ShopEmployeeProfileScreen({required this.repo, super.key});
  final ShopEmployeeRepository repo;

  @override
  Widget build(BuildContext context) {
    final employee = repo.employee ?? const <String, dynamic>{};
    final values = <(String, String, IconData)>[
      (
        'Employee name',
        '${employee['name'] ?? 'Not provided'}',
        Icons.person_outline_rounded,
      ),
      (
        'Login ID',
        '${employee['loginId'] ?? employee['employeeId'] ?? 'Not provided'}',
        Icons.badge_outlined,
      ),
      (
        'Shop',
        '${employee['shopName'] ?? 'Not provided'}',
        Icons.storefront_outlined,
      ),
      (
        'Role',
        '${employee['role'] ?? 'Not provided'}',
        Icons.verified_user_outlined,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFFEAF2FF),
                  child: Icon(Icons.person_rounded, size: 34, color: _ink),
                ),
                const SizedBox(height: 12),
                Text(
                  '${employee['name'] ?? 'Shop Employee'}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Employee account details',
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final item in values)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(item.$3, color: AppColors.primaryLight),
              title: Text(
                item.$1,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              subtitle: Text(
                item.$2,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await repo.logout();
            if (context.mounted) context.go('/login');
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class ShopVendorsScreen extends StatefulWidget {
  const ShopVendorsScreen({required this.repo, super.key});
  final ShopEmployeeRepository repo;

  @override
  State<ShopVendorsScreen> createState() => _ShopVendorsScreenState();
}

class _ShopVendorsScreenState extends State<ShopVendorsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final response = await widget.repo.request('shop/orders');
      if (!mounted) return;
      setState(
        () => _orders = (response['orders'] as List)
            .map((order) => Map<String, dynamic>.from(order as Map))
            .toList(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final order in _orders) {
      final name = '${order['vendorName'] ?? 'Vendor'}';
      final company = '${order['companyName'] ?? ''}';
      if (term.isNotEmpty &&
          !name.toLowerCase().contains(term) &&
          !company.toLowerCase().contains(term)) {
        continue;
      }
      grouped.putIfAbsent(name, () => []).add(order);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search vendors or companies',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (_error != null) _ErrorPanel(error: _error!, retry: _load),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: grouped.isEmpty && !_busy
              ? const Center(child: Text('No assigned vendors found.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final entry in grouped.entries)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ExpansionTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.storefront_outlined),
                            ),
                            title: Text(entry.key),
                            subtitle: Text(
                              '${entry.value.first['companyName'] ?? 'Company not provided'} · ${entry.value.length} assigned orders',
                            ),
                            children: [
                              for (final order in entry.value)
                                ListTile(
                                  title: Text('#${order['orderId']}'),
                                  subtitle: Text(_date(order['orderDate'])),
                                  trailing: _StatusBadge(
                                    '${order['status'] ?? 'Pending'}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class ShopDashboard extends StatefulWidget {
  const ShopDashboard({required this.repo, super.key});
  final ShopEmployeeRepository repo;
  @override
  State<ShopDashboard> createState() => _ShopDashboardState();
}

class _ShopDashboardState extends State<ShopDashboard> {
  late Future<Map<String, dynamic>> _load;
  @override
  void initState() {
    super.initState();
    _load = widget.repo.request('shop/dashboard');
  }

  Future<void> _refresh() async {
    setState(() => _load = widget.repo.request('shop/dashboard'));
    await _load;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: AppColors.waterGradientLight,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, ${widget.repo.employee?['name'] ?? 'Shop Team'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your shop at a glance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Live figures from orders, deliveries and enquiries',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FutureBuilder<Map<String, dynamic>>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                error: snapshot.error.toString(),
                retry: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final metrics = Map<String, dynamic>.from(
              snapshot.data!['metrics'] as Map,
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 620 ? 2 : 1;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  childAspectRatio: columns == 1 ? 2.7 : 1.7,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _MetricCard(
                      title: "Today's Sales",
                      value: _money(metrics['todaySales']),
                      icon: Icons.currency_rupee_rounded,
                      color: const Color(0xFF2474E5),
                    ),
                    _MetricCard(
                      title: 'Monthly Sales',
                      value: _money(metrics['monthlySales']),
                      icon: Icons.trending_up_rounded,
                      color: const Color(0xFF734CE8),
                    ),
                    _MetricCard(
                      title: "Today's Orders",
                      value: '${metrics['todayOrders'] ?? 0}',
                      icon: Icons.shopping_bag_outlined,
                      color: const Color(0xFF13A6A0),
                    ),
                    _MetricCard(
                      title: 'New Enquiries',
                      value: '${metrics['newEnquiries'] ?? 0}',
                      icon: Icons.mark_email_unread_outlined,
                      color: const Color(0xFFEA8D25),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 18),
        const Card(
          child: ListTile(
            leading: Icon(
              Icons.verified_user_outlined,
              color: AppColors.primaryLight,
            ),
            title: Text('Employee access is protected'),
            subtitle: Text(
              'Prices, stock and admin controls are read-only in this Shop App.',
            ),
          ),
        ),
      ],
    ),
  );
}

class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({
    required this.repo,
    this.deliveriesOnly = false,
    this.onNewEnquiry,
    super.key,
  });
  final ShopEmployeeRepository repo;
  final bool deliveriesOnly;
  final VoidCallback? onNewEnquiry;
  @override
  State<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends State<ShopOrdersScreen> {
  final _search = TextEditingController();
  String _status = 'All';
  String _datePreset = 'Last 7 Days';
  DateTimeRange? _customDateRange;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_shopOrdersPreviewEnabled) {
        final bounds = _dateBounds();
        final search = _search.text.trim().toLowerCase();
        _orders = buildShopOrderPreview(DateTime.now()).where((order) {
          final orderDate = DateTime.tryParse('${order['orderDate']}');
          final orderDay = orderDate == null
              ? null
              : DateTime(orderDate.year, orderDate.month, orderDate.day);
          if (bounds.$1 != null &&
              (orderDay == null || orderDay.isBefore(bounds.$1!))) {
            return false;
          }
          if (bounds.$2 != null &&
              (orderDay == null || orderDay.isAfter(bounds.$2!))) {
            return false;
          }
          final status = '${order['status'] ?? 'Pending'}'.toLowerCase();
          if (_status != 'All' && status != _status.toLowerCase()) {
            return false;
          }
          if (search.isEmpty) return true;
          final itemNames = (order['items'] as List)
              .map((item) => '${(item as Map)['name'] ?? ''}')
              .join(' ');
          final searchable = [
            order['vendorName'],
            order['companyName'],
            order['orderId'],
            itemNames,
          ].join(' ').toLowerCase();
          return searchable.contains(search);
        }).toList();
        return;
      }
      final bounds = _dateBounds();
      final result = await widget.repo.request(
        'shop/orders',
        query: {
          'search': _search.text.trim(),
          if (_status != 'All') 'status': _status.toLowerCase(),
          if (bounds.$1 != null) 'from': _isoDate(bounds.$1!),
          if (bounds.$2 != null) 'to': _isoDate(bounds.$2!),
        },
      );
      final rawOrders = result['orders'];
      if (rawOrders is! List) {
        throw Exception('The orders response was incomplete. Please refresh.');
      }
      _orders = rawOrders.map((item) {
        if (item is! Map) {
          throw Exception('The server returned an invalid order. Please refresh.');
        }
        final order = Map<String, dynamic>.from(item);
        final rawItems = order['items'];
        if (rawItems is! List) {
          throw Exception('An order is missing its product list. Please refresh.');
        }
        order['items'] = rawItems
            .whereType<Map>()
            .map((product) => Map<String, dynamic>.from(product))
            .toList();
        return order;
      }).toList();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (DateTime?, DateTime?) _dateBounds() {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_datePreset) {
      'Today' => (today, today),
      'Yesterday' => (
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      'Last 7 Days' => (today.subtract(const Duration(days: 6)), today),
      'This Month' => (DateTime(today.year, today.month), today),
      'Custom Date' => (_customDateRange?.start, _customDateRange?.end),
      _ => (null, null),
    };
  }

  String _dateRangeLabel() {
    final bounds = _dateBounds();
    if (bounds.$1 == null || bounds.$2 == null) return 'All dates';
    if (_datePreset == 'Today' || _datePreset == 'Yesterday') {
      return 'Selected date: ${_isoDate(bounds.$1!)}';
    }
    return '${_isoDate(bounds.$1!)} – ${_isoDate(bounds.$2!)}';
  }

  Future<void> _selectDatePreset(String preset) async {
    if (preset == 'Custom Date') {
      final today = DateUtils.dateOnly(DateTime.now());
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: today,
        initialDateRange:
            _customDateRange ??
            DateTimeRange(
              start: today.subtract(const Duration(days: 6)),
              end: today,
            ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _datePreset = preset;
        _customDateRange = DateTimeRange(
          start: DateUtils.dateOnly(picked.start),
          end: DateUtils.dateOnly(picked.end),
        );
      });
    } else {
      setState(() => _datePreset = preset);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(
          children: [
            TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search vendor, company, order ID or product...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _datePreset,
                    decoration: const InputDecoration(
                      labelText: 'Order date',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    items:
                        const [
                              'Today',
                              'Yesterday',
                              'Last 7 Days',
                              'This Month',
                              'Custom Date',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) _selectDatePreset(value);
                    },
                  ),
                ),
                if (_datePreset == 'Custom Date' && _customDateRange != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${_isoDate(_customDateRange!.start)} – ${_isoDate(_customDateRange!.end)}',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
              ],
            ),
            if (_datePreset != 'Custom Date')
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 5, left: 4),
                  child: Text(
                    _dateRangeLabel(),
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Pending', 'Partially Delivered', 'Delivered']
                    .map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(status),
                          selected: _status == status,
                          onSelected: (_) {
                            setState(() => _status = status);
                            _load();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (widget.onNewEnquiry != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onNewEnquiry,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('New Enquiry'),
                ),
              ),
            ],
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: _ErrorPanel(error: _error!, retry: _load),
        ),
      Expanded(
        child: _orders.isEmpty && !_busy && _error == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 38,
                      color: _muted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.deliveriesOnly
                          ? 'No orders need delivery.'
                          : 'No orders found.',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                itemBuilder: (context, index) => ShopOrderCard(
                  key: ValueKey(_orders[index]['orderId']),
                  order: _orders[index],
                  busy: _busy,
                  previewOnly: _shopOrdersPreviewEnabled,
                  save: _shopOrdersPreviewEnabled
                      ? (quantities, confirmedItems, mode, cashCollected) =>
                            _savePreviewDelivery(
                              _orders[index],
                              quantities,
                              confirmedItems,
                              cashCollected,
                            )
                      : (quantities, confirmedItems, mode, cashCollected) =>
                            _saveDelivery(
                              _orders[index],
                              quantities,
                              confirmedItems,
                              mode,
                              cashCollected,
                            ),
                ),
              ),
      ),
    ],
  );

  Future<String?> _saveDelivery(
    Map<String, dynamic> order,
    Map<int, int> quantities,
    Set<int> confirmedItems,
    String mode,
    bool cashCollected,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.request(
        'shop/orders/${Uri.encodeComponent('${order['orderId']}')}/delivery',
        method: 'POST',
        data: {
          'mode': mode,
          'cashCollected': cashCollected,
          'items': ShopEmployeeRepository.buildDeliveryItemsPayload(
            quantities,
            confirmedItems,
          ),
        },
      );
      await _load();
      return null;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _savePreviewDelivery(
    Map<String, dynamic> order,
    Map<int, int> quantities,
    Set<int> confirmedItems,
    bool cashCollected,
  ) async {
    final error = applyShopOrderPreviewDelivery(
      order,
      quantities,
      confirmedItems,
    );
    if (error != null) return error;
    if (!mounted) return 'The preview screen is no longer active.';
    setState(() {});
    return null;
  }
}

typedef ShopOrderSaveCallback = Future<String?> Function(
  Map<int, int>,
  Set<int>,
  String,
  bool,
);

class ShopOrderCard extends StatefulWidget {
  const ShopOrderCard({
    super.key,
    required this.order,
    required this.save,
    this.busy = false,
    this.previewOnly = false,
  });
  final Map<String, dynamic> order;
  final ShopOrderSaveCallback save;
  final bool busy;
  final bool previewOnly;
  @override
  State<ShopOrderCard> createState() => _ShopOrderCardState();
}

class _ShopOrderCardState extends State<ShopOrderCard> {
  List<Map<String, dynamic>> get items => (widget.order['items'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  double _orderedValue(Map<String, dynamic> item) =>
      _number(item['unitPrice']) * (int.tryParse('${item['quantity']}') ?? 0);

  Future<void> _openSupply() async {
    if (widget.busy) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ShopSupplyDialog(
        order: widget.order,
        busy: widget.busy,
        save: widget.save,
        previewOnly: widget.previewOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderedValue = items.fold<double>(
      0,
      (sum, item) => sum + _orderedValue(item),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.order['vendorName'] ?? 'Vendor'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.order['companyName'] ?? 'Company not provided'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Order #${widget.order['orderId']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge('${widget.order['status'] ?? 'Pending'}'),
              ],
            ),
            Text(
              'Order date: ${_date(widget.order['orderDate'])}  •  Due date: ${_dueDate(widget.order)}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.order['paymentMethod'] ?? 'Payment'}  •  ${_shopPaymentLabel(widget.order)}',
              style: TextStyle(
                color:
                    '${widget.order['paymentStatus']}'.toLowerCase() == 'paid'
                    ? const Color(0xFF16834A)
                    : const Color(0xFF9A5B00),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Divider(height: 18),
            Builder(
              builder: (context) {
                const quantityColumn = 66.0;
                const priceColumn = 84.0;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5ECF5)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Product Name',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: quantityColumn,
                            child: Text(
                              'Ordered Qty',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: priceColumn,
                            child: Text(
                              'Dealer Price',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      for (var index = 0; index < items.length; index++) ...[
                        if (index > 0) const Divider(height: 8),
                        _summaryItemRow(
                          items[index],
                          quantityColumn: quantityColumn,
                          priceColumn: priceColumn,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Original Order Value   ',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: _money(orderedValue),
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: widget.busy ? null : _openSupply,
                icon: const Icon(Icons.inventory_2_outlined, size: 19),
                label: const Text('Supply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItemRow(
    Map<String, dynamic> item, {
    required double quantityColumn,
    required double priceColumn,
  }) {
    final ordered = int.tryParse('${item['quantity']}') ?? 0;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 42,
                child: AppImage('${item['image']}', fit: BoxFit.contain),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${item['name'] ?? 'Product'}\n${item['sku'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: quantityColumn,
          child: Center(child: Text('$ordered')),
        ),
        SizedBox(
          width: priceColumn,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(_money(item['unitPrice'])),
          ),
        ),
      ],
    );
  }
}

class ShopSupplyDialog extends StatefulWidget {
  const ShopSupplyDialog({
    required this.order,
    required this.save,
    this.busy = false,
    this.previewOnly = false,
    super.key,
  });
  final Map<String, dynamic> order;
  final ShopOrderSaveCallback save;
  final bool busy;
  final bool previewOnly;

  @override
  State<ShopSupplyDialog> createState() => _ShopSupplyDialogState();
}

class _ShopSupplyDialogState extends State<ShopSupplyDialog> {
  late final List<Map<String, dynamic>> items;
  late final Map<int, int> quantities;
  late final Set<int> confirmedItems;
  bool _submitting = false;
  late bool _cashCollectionConfirmed;
  String? _error;

  @override
  void initState() {
    super.initState();
    items = (widget.order['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    quantities = {for (final item in items) _id(item): _initialQuantity(item)};
    confirmedItems = <int>{};
    _cashCollectionConfirmed =
        _isCod && '${widget.order['paymentStatus']}'.toLowerCase() == 'paid';
  }

  bool get _isCod => const {
    'cod',
    'cash on delivery',
  }.contains('${widget.order['paymentMethod']}'.trim().toLowerCase());

  int _id(Map<String, dynamic> item) => int.parse('${item['id']}');

  int _initialQuantity(Map<String, dynamic> item) {
    final ordered = int.tryParse('${item['quantity']}') ?? 0;
    final saved = int.tryParse('${item['deliveredQuantity']}');
    return (saved ?? (item['delivered'] == true ? ordered : 0)).clamp(
      0,
      ordered,
    );
  }

  int _ordered(Map<String, dynamic> item) =>
      int.tryParse('${item['quantity']}') ?? 0;

  double _price(Map<String, dynamic> item) => _number(item['unitPrice']);

  double get _originalValue =>
      items.fold<double>(0, (sum, item) => sum + _price(item) * _ordered(item));

  double get _deliveredValue => items.fold<double>(
    0,
    (sum, item) => sum + _price(item) * (quantities[_id(item)] ?? 0),
  );

  int get _undeliveredQuantity => items.fold<int>(
    0,
    (sum, item) => sum + _ordered(item) - (quantities[_id(item)] ?? 0),
  );

  double get _adjustment => _originalValue - _deliveredValue;

  Future<void> _confirmSupply() async {
    if (_submitting || widget.busy) return;
    final invalid = items.any((item) {
      final id = _id(item);
      final ordered = _ordered(item);
      final actual = quantities[id] ?? 0;
      return ordered <= 0 ||
          actual < 0 ||
          actual > ordered ||
          (confirmedItems.contains(id) && actual == 0);
    });
    if (invalid) {
      setState(
        () => _error = 'A delivered product must have an Actual Qty above zero, and quantities cannot exceed the ordered amount.',
      );
      return;
    }
    if (confirmedItems.isEmpty) {
      setState(
        () => _error =
            'Select at least one product that has physically been delivered.',
      );
      return;
    }
    final canConfirmCash =
        _isCod &&
        items.every((item) {
          final id = _id(item);
          return (quantities[id] ?? 0) == _ordered(item) &&
              confirmedItems.contains(id);
        });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFEF9B26),
            size: 44,
          ),
          title: const Text('Confirm Supply?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isCod
                    ? 'Confirm the products physically supplied. Cash is recorded only after you confirm it was collected.'
                    : 'Are you sure you want to confirm these products as supplied?',
              ),
              if (_isCod && canConfirmCash) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _cashCollectionConfirmed,
                  title: const Text('Cash was collected from the customer'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) => updateDialog(
                    () => _cashCollectionConfirmed = value ?? false,
                  ),
                ),
              ] else if (_isCod) ...[
                const SizedBox(height: 8),
                const Text(
                  'Cash collection remains pending until the full order is delivered.',
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.save(
      Map<int, int>.from(quantities),
      Set<int>.from(confirmedItems),
      'confirm',
      _cashCollectionConfirmed && canConfirmCash,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      setState(() => _error = 'Supply could not be saved: $error');
      return;
    }

    Navigator.of(context).pop();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 42),
        title: const Text('Success!'),
        content: Text(
          widget.previewOnly
              ? 'Sample order updated in this preview only. No backend or database records were changed.'
              : _isCod && _cashCollectionConfirmed && canConfirmCash
              ? 'Cash Collected and Products Delivered Successfully.'
              : _isCod
              ? 'Products Delivered Successfully. Cash on Delivery remains pending.'
              : 'Products Delivered Successfully.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: screen.height * .9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Supply Order',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              fit: FlexFit.loose,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '${widget.order['vendorName'] ?? 'Vendor'}  •  ${widget.order['companyName'] ?? 'Company not provided'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Order #${widget.order['orderId']}  •  Order date: ${_date(widget.order['orderDate'])}  •  Due date: ${_dueDate(widget.order)}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (screen.width < 640)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _compactItemsTable(),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        horizontalMargin: 6,
                        columnSpacing: 14,
                        headingRowHeight: 44,
                        dataRowMinHeight: 58,
                        dataRowMaxHeight: 68,
                        headingRowColor: const WidgetStatePropertyAll(
                          Color(0xFFEAF2FC),
                        ),
                        headingTextStyle: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        columns: const [
                          DataColumn(label: Text('Product Name')),
                          DataColumn(label: Text('Ordered Qty')),
                          DataColumn(label: Text('Dealer Price')),
                          DataColumn(label: Text('Actual Qty (+ / -)')),
                          DataColumn(label: Text('Delivered')),
                        ],
                        rows: [for (final item in items) _itemRow(item)],
                      ),
                    ),
                  const SizedBox(height: 12),
                  _SupplyTotals(
                    original: _originalValue,
                    delivered: _deliveredValue,
                    undelivered: _undeliveredQuantity,
                    adjustment: _adjustment,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting || widget.busy
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitting || widget.busy
                          ? null
                          : _confirmSupply,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.local_shipping_outlined),
                      label: Text(
                        _submitting ? 'Submitting…' : 'Confirm Supply',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _itemRow(Map<String, dynamic> item) {
    final ordered = _ordered(item);
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 190,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 40,
                  child: AppImage('${item['image']}', fit: BoxFit.contain),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${item['name'] ?? 'Product'}\n${item['sku'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(Text('$ordered')),
        DataCell(Text(_money(item['unitPrice']))),
        DataCell(_quantityControls(item, ordered)),
        DataCell(_deliveredCheckbox(item)),
      ],
    );
  }

  Widget _mobileItemRow(Map<String, dynamic> item) {
    final ordered = _ordered(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '${item['name'] ?? 'Product'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 42,
            child: Center(
              child: Text('$ordered', style: const TextStyle(fontSize: 11)),
            ),
          ),
          SizedBox(
            width: 58,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _money(item['unitPrice']),
                maxLines: 1,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Center(child: _quantityControls(item, ordered)),
          ),
          SizedBox(width: 44, child: Center(child: _deliveredCheckbox(item))),
        ],
      ),
    );
  }

  Widget _compactItemsTable() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5ECF5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Column(
      children: [
        const Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                'Product Name',
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                'Ordered\nQty',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                'Dealer\nPrice',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                'Actual Qty\n(+ / -)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                'Delivered',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const Divider(height: 8),
          _mobileItemRow(items[index]),
        ],
      ],
    ),
  );

  Widget _quantityControls(Map<String, dynamic> item, int ordered) {
    final id = _id(item);
    final actual = quantities[id] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease delivered quantity',
          visualDensity: VisualDensity.compact,
          onPressed: _submitting || actual <= 0
              ? null
              : () => _setActualQuantity(id, actual - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$actual', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          tooltip: 'Increase delivered quantity',
          visualDensity: VisualDensity.compact,
          onPressed: _submitting || actual >= ordered
              ? null
              : () => _setActualQuantity(id, actual + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  void _setActualQuantity(int itemId, int value) {
    if (_submitting) return;
    final item = items.firstWhere((candidate) => _id(candidate) == itemId);
    final bounded = value.clamp(0, _ordered(item)).toInt();
    setState(() {
      quantities[itemId] = bounded;
      _error = null;
    });
  }

  Widget _deliveredCheckbox(Map<String, dynamic> item) {
    final id = _id(item);
    return Tooltip(
      message: 'Mark this product as delivered',
      child: Checkbox(
        value: confirmedItems.contains(id),
        activeColor: const Color(0xFF2E9D59),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: _submitting
            ? null
            : (value) => setState(() {
                if (value == true) {
                  confirmedItems.add(id);
                } else {
                  confirmedItems.remove(id);
                }
                _error = null;
              }),
      ),
    );
  }
}

class _SupplyTotals extends StatelessWidget {
  const _SupplyTotals({
    required this.original,
    required this.delivered,
    required this.undelivered,
    required this.adjustment,
  });
  final double original;
  final double delivered;
  final int undelivered;
  final double adjustment;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF1F6FC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFD8E5F2)),
    ),
    padding: const EdgeInsets.all(14),
    child: Wrap(
      spacing: 24,
      runSpacing: 10,
      children: [
        _total(
          'Original Order Value',
          _money(original),
          AppColors.primaryLight,
        ),
        _total('Delivered Value', _money(delivered), const Color(0xFF16835D)),
        _total('Undelivered Quantity', '$undelivered', const Color(0xFFD14343)),
        _total(
          'Refund / Adjustment',
          _money(adjustment),
          const Color(0xFFD14343),
        ),
      ],
    ),
  );

  Widget _total(String label, String value, Color valueColor) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

String _dueDate(Map<String, dynamic> order) {
  final dueDate = order['dueDate'] ?? order['due_date'];
  return dueDate == null || '$dueDate'.trim().isEmpty
      ? 'Not provided'
      : _date(dueDate);
}

class ShopProductsScreen extends StatefulWidget {
  const ShopProductsScreen({required this.repo, super.key});
  final ShopEmployeeRepository repo;
  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen> {
  final _search = TextEditingController();
  String _category = '';
  String _availability = '';
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        widget.repo.request(
          'shop/products',
          query: {
            'search': _search.text,
            'category': _category,
            'availability': _availability,
          },
        ),
        widget.repo.request('shop/categories'),
      ]);
      final result = results.first;
      _products = (result['products'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _categories = (results.last['categories'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                labelText: 'Search products',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All categories'),
                      ),
                      for (final category in _categories)
                        DropdownMenuItem(
                          value: '${category['key_name']}',
                          child: Text('${category['title']}'),
                        ),
                    ],
                    onChanged: (value) {
                      _category = value ?? '';
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _availability,
                    decoration: const InputDecoration(
                      labelText: 'Availability',
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Any stock')),
                      DropdownMenuItem(
                        value: 'in_stock',
                        child: Text('In stock'),
                      ),
                      DropdownMenuItem(
                        value: 'out_of_stock',
                        child: Text('Out of stock'),
                      ),
                    ],
                    onChanged: (value) {
                      _availability = value ?? '';
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
      Expanded(
        child: _products.isEmpty && !_busy
            ? const Center(child: Text('No products found.'))
            : ListView.builder(
                itemCount: _products.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final product = _products[index];
                  final model = ProductModel.fromJson({
                    'id': product['id'],
                    'name': product['name'],
                    'sku': product['sku'],
                    'category_key': product['category_key'],
                    'category_name': product['category_name'],
                    'brand': product['brand'],
                    'mrp': product['mrp'],
                    'price': product['price'],
                    'img': product['image'],
                    'stock_quantity': product['stock'],
                  });
                  return Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 58,
                        height: 58,
                        child: AppImage(
                          model.displayImageUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                      title: Text(
                        '${product['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${product['category_name'] ?? product['category_key']} • ${product['stock']} in stock',
                      ),
                      trailing: Text(
                        _money(product['price']),
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class ShopEnquiryScreen extends StatefulWidget {
  const ShopEnquiryScreen({required this.repo, super.key});
  final ShopEmployeeRepository repo;
  @override
  State<ShopEnquiryScreen> createState() => _ShopEnquiryScreenState();
}

class _ShopEnquiryScreenState extends State<ShopEnquiryScreen> {
  final _form = GlobalKey<FormState>();
  final _controllers = List.generate(7, (_) => TextEditingController());
  bool _busy = false;
  String? _message;
  static const _labels = [
    'Customer / vendor name',
    'Company name',
    'Contact number',
    'Category',
    'Product name',
    'Required quantity',
    'Remarks',
  ];
  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.repo.request(
        'shop/enquiries',
        method: 'POST',
        data: {
          'customerName': _controllers[0].text,
          'companyName': _controllers[1].text,
          'contactNumber': _controllers[2].text,
          'category': _controllers[3].text,
          'productName': _controllers[4].text,
          'requiredQuantity': int.tryParse(_controllers[5].text),
          'remarks': _controllers[6].text,
        },
      );
      for (final controller in _controllers) {
        controller.clear();
      }
      setState(() => _message = '${result['message']}');
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Unavailable product request',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'The enquiry is saved to the database and appears in the admin workspace.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: _controllers[i],
              keyboardType: i == 2 || i == 5
                  ? TextInputType.number
                  : TextInputType.text,
              maxLines: i == 6 ? 3 : 1,
              decoration: InputDecoration(
                labelText: _labels[i],
                prefixIcon: Icon(
                  [
                    Icons.person_outline,
                    Icons.business_outlined,
                    Icons.phone_outlined,
                    Icons.category_outlined,
                    Icons.inventory_2_outlined,
                    Icons.numbers,
                    Icons.notes_outlined,
                  ][i],
                ),
              ),
              validator: i == 6
                  ? null
                  : (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : i == 5 && int.tryParse(value) == null
                        ? 'Enter a quantity'
                        : null,
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _message!,
              style: TextStyle(
                color: _message!.startsWith('Exception')
                    ? Colors.red
                    : Colors.green,
              ),
            ),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.send_rounded),
          label: Text(_busy ? 'Sending…' : 'Send enquiry'),
        ),
      ],
    ),
  );
}

class ShopReportsScreen extends StatefulWidget {
  const ShopReportsScreen({required this.repo, super.key});
  final ShopEmployeeRepository repo;
  @override
  State<ShopReportsScreen> createState() => _ShopReportsScreenState();
}

class _ShopReportsScreenState extends State<ShopReportsScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _product = TextEditingController();
  String _period = 'daily';
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _product.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repo.request(
        'shop/reports',
        query: {
          'from': _from.text,
          'to': _to.text,
          'product': _product.text,
          'period': _period,
        },
      );
      _rows = (result['rows'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _totals = Map<String, dynamic>.from(result['totals'] as Map);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sales by date and product',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Report grouping'),
              items: const [
                DropdownMenuItem(
                  value: 'daily',
                  child: Text('Daily / date-wise'),
                ),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'product', child: Text('Product-wise')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _period = value;
                  _load();
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    decoration: const InputDecoration(
                      labelText: 'From YYYY-MM-DD',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _to,
                    decoration: const InputDecoration(
                      labelText: 'To YYYY-MM-DD',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _product,
                    decoration: const InputDecoration(
                      labelText: 'Product name / SKU',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.filter_alt_rounded),
                ),
              ],
            ),
            if (_totals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Qty ${_totals['quantitySold']}  •  Delivered ${_money(_totals['deliveredAmount'])}  •  Pending ${_money(_totals['pendingAmount'])}  •  Refund ${_money(_totals['refundAmount'])}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: _rows.length,
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final row = _rows[index];
            return Card(
              child: ListTile(
                title: Text(
                  '${row['productName']}  •  ${row['quantitySold']} sold',
                ),
                subtitle: Text(
                  '${row['sale_date']} • delivered ${_money(row['deliveredAmount'])} • pending ${_money(row['pendingAmount'])} • refund ${_money(row['refundAmount'])}',
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: _muted)),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final partial = text.toLowerCase().contains('partial');
    final done = text.toLowerCase() == 'delivered';
    final pending =
        text.toLowerCase().contains('pending') ||
        text.toLowerCase().contains('undelivered');
    final color = done
        ? const Color(0xFF138A63)
        : partial
        ? const Color(0xFFCC7A13)
        : pending
        ? const Color(0xFFDC2626)
        : const Color(0xFF4775BA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.retry});
  final String error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: const Text('Could not load shop data'),
      subtitle: Text(error),
      trailing: IconButton(onPressed: retry, icon: const Icon(Icons.refresh)),
    ),
  );
}

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _shopPaymentLabel(Map<String, dynamic> order) {
  final status = '${order['paymentStatus'] ?? 'pending'}'.toLowerCase();
  if (status == 'paid') return 'Paid';
  final method = '${order['paymentMethod'] ?? ''}'.toLowerCase();
  return method.contains('cash') || method == 'cod'
      ? 'Cash on Delivery · Pending'
      : 'Payment Pending';
}

String _money(Object? value) =>
    '\u20B9${(value is num ? value : num.tryParse('$value') ?? 0).toStringAsFixed(2)}';

String _date(Object? value) {
  if (value == null) return 'Date unavailable';
  final parsed = DateTime.tryParse('$value');
  return parsed == null
      ? '$value'
      : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
