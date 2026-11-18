import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../products/domain/models/product_model.dart';
import '../data/shop_employee_repository.dart';
import '../data/shop_orders_preview.dart';
import 'shop_ui.dart';

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

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Center(child: BrandLogo(width: 220, height: 80)),
      const SizedBox(height: 18),
      const Text(
        'Shop Employee Login',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: ShopColors.ink,
          letterSpacing: -0.2,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Sign in with the Login ID and password provided by your administrator.',
        textAlign: TextAlign.center,
        style: TextStyle(color: ShopColors.muted, height: 1.45),
      ),
      const SizedBox(height: 26),
      TextField(
        controller: _id,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Employee ID / Login ID',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
      ),
      const SizedBox(height: 14),
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
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF6C7C7)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: ShopColors.danger,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: ShopColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      SizedBox(
        height: 50,
        child: FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Login'),
        ),
      ),
    ],
  );

  Widget _brandPanel() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0E2340), Color(0xFF0F4C9E), Color(0xFF1F7AE0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    padding: const EdgeInsets.all(48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandLogo(
          width: 180,
          height: 64,
          onDark: true,
          alignment: Alignment.centerLeft,
        ),
        const Spacer(),
        const Text(
          'SHOP APP',
          style: TextStyle(
            color: Color(0xFFBFD6FF),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Orders, deliveries and\nenquiries in one place.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 26),
        for (final (icon, text) in const [
          (Icons.receipt_long_outlined, 'Track current orders and supply'),
          (
            Icons.local_shipping_outlined,
            'Confirm deliveries and cash collection',
          ),
          (Icons.query_stats_outlined, 'Review daily and monthly sales'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFDCE8FF),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: shopTheme(),
    child: Scaffold(
      backgroundColor: ShopColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final card = Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(constraints.maxWidth < 480 ? 16 : 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ShopPanel(
                  padding: EdgeInsets.all(constraints.maxWidth < 480 ? 22 : 32),
                  child: _form(),
                ),
              ),
            ),
          );
          if (!wide) return card;
          return Row(
            children: [
              Expanded(flex: 5, child: _brandPanel()),
              Expanded(flex: 6, child: card),
            ],
          );
        },
      ),
    ),
  );
}

class ShopAppScreen extends StatefulWidget {
  const ShopAppScreen({super.key, this.repository});

  /// Defaults to the app-wide repository; tests pass their own.
  final ShopEmployeeRepository? repository;
  @override
  State<ShopAppScreen> createState() => _ShopAppScreenState();
}

class _ShopAppScreenState extends State<ShopAppScreen> {
  late final _repo = widget.repository ?? ShopEmployeeRepository.instance;
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

  static const _destinations = [
    ('Overview', Icons.space_dashboard_outlined),
    ('Current Orders', Icons.receipt_long_outlined),
    ('Deliveries', Icons.local_shipping_outlined),
    ('Vendors', Icons.people_alt_outlined),
    ('Products', Icons.inventory_2_outlined),
    ('New Enquiries', Icons.add_business_outlined),
    ('Sales Reports', Icons.query_stats_outlined),
    ('Profile', Icons.person_outline_rounded),
  ];

  static const _subtitles = [
    'Live figures from orders, deliveries and enquiries',
    'Orders assigned to your shop',
    'Orders waiting for delivery',
    'Vendors and companies you supply',
    'Read-only catalogue with stock and dealer prices',
    'Request products that are not in the catalogue',
    'Sales by date and product',
    'Your employee account',
  ];

  Future<void> _signOut() async {
    await _repo.logout();
    if (!mounted) return;
    context.go('/login');
  }

  void _refreshCurrent() {
    if (_tab == 1) _ordersKey.currentState?.refresh();
    if (_tab == 2) _deliveriesKey.currentState?.refresh();
  }

  Widget? _refreshButton() => (_tab == 1 || _tab == 2)
      ? IconButton(
          tooltip: _tab == 1 ? 'Refresh orders' : 'Refresh',
          onPressed: _refreshCurrent,
          icon: const Icon(Icons.refresh_rounded),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Theme(
        data: shopTheme(),
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final pages = [
      ShopDashboard(repo: _repo),
      ShopOrdersScreen(
        key: _ordersKey,
        repo: _repo,
        active: _tab == 1,
        onNewEnquiry: () => setState(() => _tab = 5),
      ),
      ShopOrdersScreen(
        key: _deliveriesKey,
        repo: _repo,
        deliveriesOnly: true,
        active: _tab == 2,
        onNewEnquiry: () => setState(() => _tab = 5),
      ),
      ShopVendorsScreen(repo: _repo),
      ShopProductsScreen(repo: _repo),
      ShopEnquiryScreen(repo: _repo),
      ShopReportsScreen(repo: _repo),
      ShopEmployeeProfileScreen(repo: _repo),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    return Theme(
      data: shopTheme(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (width >= ShopBreakpoints.tablet) {
            final compact = width < ShopBreakpoints.desktop;
            return Scaffold(
              body: Row(
                children: [
                  _ShopSidebar(
                    destinations: _destinations,
                    selected: _tab,
                    compact: compact,
                    onSelect: (index) => setState(() => _tab = index),
                    onSignOut: _signOut,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _ShopTopBar(
                          title: _destinations[_tab].$1,
                          subtitle: _subtitles[_tab],
                          employee: _repo.employee,
                          refresh: _refreshButton(),
                          gutter: shopGutter(width),
                        ),
                        Expanded(child: SafeArea(top: false, child: body)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return _mobileShell(body);
        },
      ),
    );
  }

  Widget _mobileShell(Widget body) {
    const bottomDestinations = <(String, IconData, int)>[
      ('Current Orders', Icons.receipt_long_outlined, 1),
      ('Products', Icons.inventory_2_outlined, 4),
      ('Enquiries', Icons.add_business_outlined, 5),
      ('Profile', Icons.person_outline_rounded, 7),
    ];
    final bottomSelection = bottomDestinations.indexWhere(
      (destination) => destination.$3 == _tab,
    );
    final refresh = _refreshButton();
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_tab].$1),
        actions: [if (refresh != null) refresh, const SizedBox(width: 4)],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ShopColors.border)),
        ),
        child: NavigationBar(
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
      ),
      drawer: NavigationDrawer(
        backgroundColor: ShopColors.surface,
        indicatorColor: ShopColors.primarySoft,
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
                BrandLogo(
                  width: 160,
                  height: 58,
                  alignment: Alignment.centerLeft,
                ),
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
          for (var index = 0; index < _destinations.length; index++)
            NavigationDrawerDestination(
              icon: Icon(_destinations[index].$2),
              label: Text(_destinations[index].$1),
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
              await _signOut();
            },
          ),
        ],
      ),
    );
  }
}

/// Dark navigation sidebar (desktop) / icon rail (tablet).
class _ShopSidebar extends StatelessWidget {
  const _ShopSidebar({
    required this.destinations,
    required this.selected,
    required this.compact,
    required this.onSelect,
    required this.onSignOut,
  });

  final List<(String, IconData)> destinations;
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSignOut;

  Widget _item(String label, IconData icon, bool active, VoidCallback onTap) {
    final tile = Material(
      color: active ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: Colors.white.withValues(alpha: 0.06),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
          decoration: active
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xFF5EA2FF), width: 3),
                  ),
                )
              : null,
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 21,
                color: active ? Colors.white : ShopColors.sidebarMuted,
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : ShopColors.sidebarMuted,
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        child: compact ? Tooltip(message: label, child: tile) : tile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 76 : 248,
    color: ShopColors.sidebar,
    child: SafeArea(
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 22,
              22,
              compact ? 16 : 12,
              18,
            ),
            child: compact
                ? Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ShopColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                    ),
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BrandLogo(
                        width: 150,
                        height: 52,
                        onDark: true,
                        alignment: Alignment.centerLeft,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'SHOP APP',
                        style: TextStyle(
                          color: ShopColors.sidebarMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 16, 10),
              child: Text(
                'MENU',
                style: TextStyle(
                  color: Color(0xFF6F86A6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
              children: [
                for (var i = 0; i < destinations.length; i++)
                  _item(
                    destinations[i].$1,
                    destinations[i].$2,
                    i == selected,
                    () => onSelect(i),
                  ),
              ],
            ),
          ),
          const Divider(color: Color(0x1FFFFFFF), height: 1),
          Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: _item('Sign out', Icons.logout_rounded, false, onSignOut),
          ),
        ],
      ),
    ),
  );
}

/// Page title bar with the employee chip (tablet & desktop).
class _ShopTopBar extends StatelessWidget {
  const _ShopTopBar({
    required this.title,
    required this.subtitle,
    required this.employee,
    required this.refresh,
    required this.gutter,
  });

  final String title;
  final String subtitle;
  final Map<String, dynamic>? employee;
  final Widget? refresh;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final name = '${employee?['name'] ?? 'Shop Employee'}';
    final shop = '${employee?['shopName'] ?? ''}';
    return Container(
      decoration: const BoxDecoration(
        color: ShopColors.surface,
        border: Border(bottom: BorderSide(color: ShopColors.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 14),
      child: SafeArea(
        bottom: false,
        left: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShopColors.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShopColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (refresh != null)
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: ShopColors.borderStrong),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: refresh,
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: ShopColors.subtle,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ShopColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShopAvatar(name: name, size: 32),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ShopColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (shop.isNotEmpty)
                          Text(
                            shop,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ShopColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
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
    final name = '${employee['name'] ?? 'Shop Employee'}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = shopGutter(constraints.maxWidth);
        final twoColumns = constraints.maxWidth >= 760;
        final summary = ShopPanel(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ShopAvatar(name: name, size: 76),
              const SizedBox(height: 14),
              Text(
                name,
                textAlign: TextAlign.center,
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
              const SizedBox(height: 14),
              ShopPill(
                label: '${employee['shopName'] ?? 'Shop'}',
                icon: Icons.storefront_outlined,
                color: ShopColors.primary,
                background: ShopColors.primarySoft,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await repo.logout();
                    if (context.mounted) context.go('/login');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ShopColors.danger,
                    side: const BorderSide(color: Color(0xFFF2C4C4)),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        );
        final details = ShopPanel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account information',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Managed by your shop administrator.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ShopColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          values[i].$3,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              values[i].$1,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              values[i].$2,
                              style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 24),
          children: [
            ShopContent(
              maxWidth: 980,
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 300, child: summary),
                        const SizedBox(width: 20),
                        Expanded(child: details),
                      ],
                    )
                  : Column(
                      children: [summary, const SizedBox(height: 16), details],
                    ),
            ),
          ],
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = shopGutter(constraints.maxWidth);
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 12),
              child: ShopContent(
                child: Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Search vendors or companies',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                    ),
                    if (constraints.maxWidth >= 600) ...[
                      const SizedBox(width: 16),
                      ShopPill(
                        label: '${grouped.length} vendors',
                        icon: Icons.people_alt_outlined,
                        color: ShopColors.primary,
                        background: ShopColors.primarySoft,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: ShopContent(
                  child: _ErrorPanel(error: _error!, retry: _load),
                ),
              ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: grouped.isEmpty && !_busy
                  ? const Center(
                      child: ShopEmptyState(
                        icon: Icons.people_alt_outlined,
                        message: 'No assigned vendors found.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 24),
                        children: [
                          for (final entry in grouped.entries)
                            ShopContent(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 6,
                                      ),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            12,
                                            10,
                                          ),
                                      leading: ShopAvatar(name: entry.key),
                                      title: Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: _ink,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${entry.value.first['companyName'] ?? 'Company not provided'} · ${entry.value.length} assigned orders',
                                      ),
                                      children: [
                                        for (final order in entry.value)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: ShopColors.subtle,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: ShopColors.border,
                                              ),
                                            ),
                                            child: ListTile(
                                              dense: true,
                                              leading: const Icon(
                                                Icons.receipt_long_outlined,
                                              ),
                                              title: Text(
                                                '#${order['orderId']}',
                                              ),
                                              subtitle: Text(
                                                _date(order['orderDate']),
                                              ),
                                              trailing: _StatusBadge(
                                                '${order['status'] ?? 'Pending'}',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gutter = shopGutter(constraints.maxWidth);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 28),
          children: [
            ShopContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0E2340),
                          Color(0xFF0F4C9E),
                          Color(0xFF2A84F0),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${widget.repo.employee?['name'] ?? 'Shop Team'}',
                                style: const TextStyle(
                                  color: Color(0xFFCFE0FF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Your shop at a glance',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Live figures from orders, deliveries and enquiries',
                                style: TextStyle(color: Color(0xFFCFE0FF)),
                              ),
                            ],
                          ),
                        ),
                        if (constraints.maxWidth >= 600)
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
                        builder: (context, inner) {
                          final columns = inner.maxWidth >= 980
                              ? 4
                              : (inner.maxWidth >= 520 ? 2 : 1);
                          return GridView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  mainAxisExtent: 104,
                                ),
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
                  const SizedBox(height: 20),
                  ShopPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: ShopColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.primaryLight,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Employee access is protected',
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Prices, stock and admin controls are read-only in this Shop App.',
                                style: TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({
    required this.repo,
    this.deliveriesOnly = false,
    this.onNewEnquiry,
    this.active = true,
    this.refreshInterval = const Duration(seconds: 30),
    super.key,
  });
  final ShopEmployeeRepository repo;
  final bool deliveriesOnly;
  final VoidCallback? onNewEnquiry;

  /// Whether this page is on screen. Only the visible page refreshes itself,
  /// and it refreshes as soon as it becomes visible again.
  final bool active;

  /// How often new customer orders are fetched while the page is visible.
  final Duration refreshInterval;
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
  Timer? _autoRefresh;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_shopOrdersPreviewEnabled) {
      // New customer orders appear without pressing Refresh.
      _autoRefresh = Timer.periodic(widget.refreshInterval, (_) => _poll());
      _lifecycle = AppLifecycleListener(onResume: _poll);
    }
  }

  @override
  void didUpdateWidget(ShopOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _poll();
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _lifecycle?.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() => _load();

  /// Background refresh: keeps the current list on screen (no progress bar,
  /// Supply stays enabled) and ignores temporary network errors.
  void _poll() {
    if (!mounted || !widget.active || _busy) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
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
          throw Exception(
            'The server returned an invalid order. Please refresh.',
          );
        }
        final order = Map<String, dynamic>.from(item);
        final rawItems = order['items'];
        if (rawItems is! List) {
          throw Exception(
            'An order is missing its product list. Please refresh.',
          );
        }
        order['items'] = rawItems
            .whereType<Map>()
            .map((product) => Map<String, dynamic>.from(product))
            .toList();
        return order;
      }).toList();
    } catch (error) {
      if (!silent) _error = error.toString();
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

  Widget _searchField() => TextField(
    controller: _search,
    onSubmitted: (_) => _load(),
    decoration: InputDecoration(
      hintText: 'Search vendor, company, order ID or product...',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: IconButton(
        tooltip: 'Search',
        onPressed: _load,
        icon: const Icon(Icons.arrow_forward),
      ),
    ),
  );

  Widget _dateFilter() => DropdownButtonFormField<String>(
    initialValue: _datePreset,
    isExpanded: true,
    borderRadius: BorderRadius.circular(12),
    dropdownColor: Colors.white,
    decoration: const InputDecoration(
      labelText: 'Order date',
      prefixIcon: Icon(Icons.calendar_month_outlined),
    ),
    items:
        const ['Today', 'Yesterday', 'Last 7 Days', 'This Month', 'Custom Date']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
    onChanged: (value) {
      if (value != null) _selectDatePreset(value);
    },
  );

  Widget _statusTabs({bool scrollable = false}) {
    final chips = ['All', 'Pending', 'Partially Delivered', 'Delivered']
        .map(
          (status) => ChoiceChip(
            label: Text(status),
            selected: _status == status,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              setState(() => _status = status);
              _load();
            },
          ),
        )
        .toList();
    if (scrollable) {
      return Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _rangeLabel() {
    final text = _datePreset == 'Custom Date' && _customDateRange != null
        ? '${_isoDate(_customDateRange!.start)} – ${_isoDate(_customDateRange!.end)}'
        : _dateRangeLabel();
    return ShopPill(label: text, icon: Icons.event_outlined);
  }

  Widget _newEnquiryButton({bool expand = false}) {
    final button = FilledButton.tonalIcon(
      onPressed: widget.onNewEnquiry,
      style: FilledButton.styleFrom(
        backgroundColor: ShopColors.primarySoft,
        foregroundColor: ShopColors.primary,
        minimumSize: const Size(0, 48),
      ),
      icon: const Icon(Icons.add_business_outlined),
      label: const Text('New Enquiry'),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _toolbar(bool wide) => ShopPanel(
    padding: EdgeInsets.all(wide ? 16 : 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 12),
              SizedBox(width: 230, child: _dateFilter()),
              if (widget.onNewEnquiry != null) ...[
                const SizedBox(width: 12),
                _newEnquiryButton(),
              ],
            ],
          )
        else ...[
          _searchField(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _dateFilter()),
              if (widget.onNewEnquiry != null) ...[
                const SizedBox(width: 10),
                _newEnquiryButton(),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _datePreset == 'Custom Date' && _customDateRange != null
                  ? '${_isoDate(_customDateRange!.start)} – ${_isoDate(_customDateRange!.end)}'
                  : _dateRangeLabel(),
              style: const TextStyle(color: _muted, fontSize: 11.5),
            ),
          ),
        ],
        SizedBox(height: wide ? 14 : 10),
        if (wide)
          Row(
            children: [
              Expanded(child: _statusTabs()),
              const SizedBox(width: 12),
              _rangeLabel(),
            ],
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _statusTabs(scrollable: true),
          ),
      ],
    ),
  );

  Widget _orderCard(int index) => ShopOrderCard(
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
        : (quantities, confirmedItems, mode, cashCollected) => _saveDelivery(
            _orders[index],
            quantities,
            confirmedItems,
            mode,
            cashCollected,
          ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gutter = shopGutter(width);
      final wide = width >= 860;
      final empty = _orders.isEmpty && !_busy && _error == null;
      final emptyState = ShopEmptyState(
        icon: Icons.receipt_long_outlined,
        message: widget.deliveriesOnly
            ? 'No orders need delivery.'
            : 'No orders found.',
        detail: 'Try another date range or status filter.',
      );
      // Header blocks shown above the order list.
      final header = <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 10),
          child: ShopContent(child: _toolbar(wide)),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 6),
            child: ShopContent(
              child: _ErrorPanel(error: _error!, retry: _load),
            ),
          ),
        if (_orders.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 8),
            child: ShopContent(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_orders.length} ${_orders.length == 1 ? 'order' : 'orders'}',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ];
      final progress = _busy
          ? const LinearProgressIndicator(minHeight: 2)
          : const SizedBox(height: 2);

      if (!wide) {
        // Phones: the filters scroll away with the orders.
        return Column(
          children: [
            progress,
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(bottom: 24),
                itemCount: header.length + (empty ? 1 : _orders.length),
                itemBuilder: (context, index) {
                  if (index < header.length) return header[index];
                  if (empty) return emptyState;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: ShopContent(
                      child: _orderCard(index - header.length),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }

      // Desktop / tablet: filters stay pinned above the scrolling orders.
      return Column(
        children: [
          ...header.take(1),
          progress,
          ...header.skip(1),
          Expanded(
            child: empty
                ? Center(child: emptyState)
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) =>
                        ShopContent(child: _orderCard(index)),
                  ),
          ),
        ],
      );
    },
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

  /// Cancelled by the administrator: nothing can be supplied.
  bool get _cancelled =>
      '${widget.order['status']}'.trim().toLowerCase() == 'cancelled';

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

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final orderedValue = items.fold<double>(
      0,
      (sum, item) => sum + _orderedValue(item),
    );
    final paid = '${widget.order['paymentStatus']}'.toLowerCase() == 'paid';
    final vendor = '${widget.order['vendorName'] ?? 'Vendor'}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: ShopColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? const Color(0xFFC9D8EE) : ShopColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F2744)
                  .withValues(alpha: _hovered ? 0.08 : 0.04),
              blurRadius: _hovered ? 22 : 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 640;
            return Padding(
              padding: EdgeInsets.all(wide ? 20 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopAvatar(name: vendor, size: wide ? 44 : 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vendor,
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
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusBadge('${widget.order['status'] ?? 'Pending'}'),
                    ],
                  ),
                  SizedBox(height: wide ? 14 : 10),
                  if (!wide)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${widget.order['orderId']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Order date: ${_date(widget.order['orderDate'])}  •  Due date: ${_dueDate(widget.order)}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.order['paymentMethod'] ?? 'Payment'}  •  ${_shopPaymentLabel(widget.order)}',
                          style: TextStyle(
                            color: paid
                                ? const Color(0xFF16834A)
                                : const Color(0xFF9A5B00),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShopPill(
                          label: 'Order #${widget.order['orderId']}',
                          icon: Icons.tag_rounded,
                          color: _ink,
                        ),
                        ShopPill(
                          label:
                              'Order date: ${_date(widget.order['orderDate'])}',
                          icon: Icons.event_outlined,
                        ),
                        ShopPill(
                          label: 'Due date: ${_dueDate(widget.order)}',
                          icon: Icons.schedule_rounded,
                        ),
                        ShopPill(
                          label:
                              '${widget.order['paymentMethod'] ?? 'Payment'}  •  ${_shopPaymentLabel(widget.order)}',
                          icon: paid
                              ? Icons.check_circle_outline_rounded
                              : Icons.payments_outlined,
                          color: paid
                              ? const Color(0xFF16834A)
                              : const Color(0xFF9A5B00),
                          background: paid
                              ? const Color(0xFFE6F6EE)
                              : const Color(0xFFFFF4E0),
                        ),
                      ],
                    ),
                  SizedBox(height: wide ? 16 : 12),
                  Builder(
                    builder: (context) {
                      final quantityColumn = wide ? 110.0 : 66.0;
                      final priceColumn = wide ? 130.0 : 84.0;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ShopColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              color: ShopColors.subtle,
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? 14 : 10,
                                vertical: wide ? 10 : 8,
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: ShopTableHeading('Product Name'),
                                  ),
                                  SizedBox(
                                    width: quantityColumn,
                                    child: const ShopTableHeading(
                                      'Ordered Qty',
                                      align: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    width: priceColumn,
                                    child: const ShopTableHeading(
                                      'Dealer Price',
                                      align: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (
                              var index = 0;
                              index < items.length;
                              index++
                            ) ...[
                              const Divider(),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: wide ? 14 : 10,
                                  vertical: wide ? 10 : 7,
                                ),
                                child: _summaryItemRow(
                                  items[index],
                                  quantityColumn: quantityColumn,
                                  priceColumn: priceColumn,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: wide ? 16 : 12),
                  Flex(
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: wide
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: wide ? 1 : 0,
                        fit: FlexFit.loose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: ShopColors.primarySoft,
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
                      ),
                      SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 10),
                      SizedBox(
                        width: wide ? 190 : double.infinity,
                        height: wide ? 46 : 44,
                        child: FilledButton.icon(
                          onPressed: widget.busy || _cancelled
                              ? null
                              : _openSupply,
                          icon: Icon(
                            _cancelled
                                ? Icons.block_rounded
                                : Icons.inventory_2_outlined,
                            size: 19,
                          ),
                          label: Text(
                            _cancelled ? 'Order cancelled' : 'Supply',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
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
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ShopColors.border),
                ),
                child: AppImage(_orderItemImage(item), fit: BoxFit.contain),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${item['name'] ?? 'Product'}\n${item['sku'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: quantityColumn,
          child: Center(
            child: Text(
              '$ordered',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        SizedBox(
          width: priceColumn,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              _money(item['unitPrice']),
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ShopColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: ShopColors.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Supply Order',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink,
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
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${widget.order['vendorName'] ?? 'Vendor'}  •  ${widget.order['companyName'] ?? 'Company not provided'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Order #${widget.order['orderId']}  •  Order date: ${_date(widget.order['orderDate'])}  •  Due date: ${_dueDate(widget.order)}',
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  if (screen.width < 640)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _compactItemsTable(),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ShopColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: box.maxWidth - 2,
                            ),
                            child: DataTable(
                              horizontalMargin: 14,
                              columnSpacing: 14,
                              headingRowHeight: 44,
                              dataRowMinHeight: 58,
                              dataRowMaxHeight: 68,
                              headingRowColor: const WidgetStatePropertyAll(
                                ShopColors.subtle,
                              ),
                              dividerThickness: 1,
                              headingTextStyle: const TextStyle(
                                color: _ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              columns: const [
                                DataColumn(
                                  label: Text('Product Name'),
                                  columnWidth: MaxColumnWidth(
                                    FixedColumnWidth(220),
                                    FlexColumnWidth(),
                                  ),
                                ),
                                DataColumn(label: Text('Ordered Qty')),
                                DataColumn(label: Text('Dealer Price')),
                                DataColumn(label: Text('Actual Qty (+ / -)')),
                                DataColumn(label: Text('Delivered')),
                              ],
                              rows: [for (final item in items) _itemRow(item)],
                            ),
                          ),
                        ),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF6C7C7)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                  child: AppImage(_orderItemImage(item), fit: BoxFit.contain),
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
      color: ShopColors.subtle,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ShopColors.border),
    ),
    padding: const EdgeInsets.all(16),
    child: Wrap(
      spacing: 24,
      runSpacing: 14,
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
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
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

  Widget _filters(bool wide) {
    final search = TextField(
      controller: _search,
      onSubmitted: (_) => _load(),
      decoration: const InputDecoration(
        labelText: 'Search products',
        prefixIcon: Icon(Icons.search),
      ),
    );
    final category = DropdownButtonFormField<String>(
      initialValue: _category,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      dropdownColor: Colors.white,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('All categories')),
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
    );
    final availability = DropdownButtonFormField<String>(
      initialValue: _availability,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      dropdownColor: Colors.white,
      decoration: const InputDecoration(
        labelText: 'Availability',
        prefixIcon: Icon(Icons.inventory_outlined),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('Any stock')),
        DropdownMenuItem(value: 'in_stock', child: Text('In stock')),
        DropdownMenuItem(value: 'out_of_stock', child: Text('Out of stock')),
      ],
      onChanged: (value) {
        _availability = value ?? '';
        _load();
      },
    );
    return ShopPanel(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: search),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: category),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: availability),
              ],
            )
          : Column(
              children: [
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: category),
                    const SizedBox(width: 10),
                    Expanded(child: availability),
                  ],
                ),
              ],
            ),
    );
  }

  ProductModel _model(Map<String, dynamic> product) => ProductModel.fromJson({
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
    'moq': product['moq'],
    'max_order_quantity': product['maxOrderQuantity'],
  });

  Widget _stockBadge(Map<String, dynamic> product) {
    // Real stock (never the PDF quantity); the PDF quantity is the most a
    // customer can order per line.
    final model = _model(product);
    final stock = int.tryParse('${product['stock']}') ?? 0;
    final inStock = stock > 0;
    final max = model.maxOrderQuantity;
    return ShopPill(
      label: inStock
          ? '$stock in stock${max == null ? '' : ' · max $max/order'}'
          : 'Out of stock${max == null ? '' : ' · max $max/order'}',
      icon: inStock ? Icons.check_circle_outline_rounded : Icons.block_rounded,
      color: inStock ? ShopColors.success : ShopColors.danger,
      background: inStock ? const Color(0xFFE6F6EE) : const Color(0xFFFDECEC),
    );
  }

  Widget _productTile(Map<String, dynamic> product) {
    final model = _model(product);
    return ShopPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 150,
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShopColors.subtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppImage(model.displayImageUrl, fit: BoxFit.contain),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['category_name'] ?? product['category_key']}'
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShopColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      height: 1.3,
                    ),
                  ),
                  if ('${product['sku'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'SKU ${product['sku']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(product['price']),
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      Flexible(child: _stockBadge(product)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(Map<String, dynamic> product) {
    final model = _model(product);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShopPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ShopColors.subtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AppImage(model.displayImageUrl, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${product['category_name'] ?? product['category_key']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  _stockBadge(product),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money(product['price']),
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gutter = shopGutter(width);
      final content = width - gutter * 2;
      final columns = content >= 1080
          ? 4
          : content >= 800
          ? 3
          : content >= 520
          ? 2
          : 1;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 10),
            child: ShopContent(child: _filters(width >= 760)),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 6),
              child: ShopContent(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          if (_products.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 4),
              child: ShopContent(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_products.length} products',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _products.isEmpty && !_busy
                ? const Center(
                    child: ShopEmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No products found.',
                    ),
                  )
                : columns == 1
                ? ListView.builder(
                    itemCount: _products.length,
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
                    itemBuilder: (context, index) =>
                        _productRow(_products[index]),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 1240 + gutter * 2),
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 318,
                        ),
                        itemCount: _products.length,
                        itemBuilder: (context, index) =>
                            _productTile(_products[index]),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
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

  Widget _field(int i) => TextFormField(
    controller: _controllers[i],
    keyboardType: i == 2 || i == 5 ? TextInputType.number : TextInputType.text,
    maxLines: i == 6 ? 3 : 1,
    decoration: InputDecoration(
      labelText: _labels[i],
      alignLabelWithHint: i == 6,
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
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gutter = shopGutter(constraints.maxWidth);
      final wide = constraints.maxWidth >= 760;
      Widget pair(int a, int b) => wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(a)),
                const SizedBox(width: 16),
                Expanded(child: _field(b)),
              ],
            )
          : Column(
              children: [_field(a), const SizedBox(height: 14), _field(b)],
            );
      final success = _message != null && !_message!.startsWith('Exception');
      return Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 28),
          children: [
            ShopContent(
              maxWidth: 900,
              child: ShopPanel(
                padding: EdgeInsets.all(wide ? 26 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 22),
                    const _FormSectionTitle(
                      'Customer details',
                      Icons.person_outline,
                    ),
                    const SizedBox(height: 14),
                    pair(0, 1),
                    const SizedBox(height: 14),
                    _field(2),
                    const SizedBox(height: 24),
                    const _FormSectionTitle(
                      'Product request',
                      Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: 14),
                    pair(3, 4),
                    const SizedBox(height: 14),
                    _field(5),
                    const SizedBox(height: 14),
                    _field(6),
                    const SizedBox(height: 18),
                    if (_message != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: success
                              ? const Color(0xFFE6F6EE)
                              : const Color(0xFFFDECEC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: success ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Align(
                      alignment: wide
                          ? Alignment.centerRight
                          : Alignment.center,
                      child: SizedBox(
                        width: wide ? 220 : double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.send_rounded),
                          label: Text(_busy ? 'Sending…' : 'Send enquiry'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: ShopColors.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w800,
          fontSize: 14.5,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Divider()),
    ],
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

  Widget _filters(bool wide) {
    final grouping = DropdownButtonFormField<String>(
      initialValue: _period,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      dropdownColor: Colors.white,
      decoration: const InputDecoration(
        labelText: 'Report grouping',
        prefixIcon: Icon(Icons.view_agenda_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 'daily', child: Text('Daily / date-wise')),
        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
        DropdownMenuItem(value: 'product', child: Text('Product-wise')),
      ],
      onChanged: (value) {
        if (value != null) {
          _period = value;
          _load();
        }
      },
    );
    final from = TextField(
      controller: _from,
      decoration: const InputDecoration(
        labelText: 'From YYYY-MM-DD',
        prefixIcon: Icon(Icons.event_outlined),
      ),
    );
    final to = TextField(
      controller: _to,
      decoration: const InputDecoration(
        labelText: 'To YYYY-MM-DD',
        prefixIcon: Icon(Icons.event_outlined),
      ),
    );
    final product = TextField(
      controller: _product,
      onSubmitted: (_) => _load(),
      decoration: const InputDecoration(
        labelText: 'Product name / SKU',
        prefixIcon: Icon(Icons.search),
      ),
    );
    final apply = SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.filter_alt_rounded),
        label: const Text('Apply'),
      ),
    );
    return ShopPanel(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 4, child: grouping),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: from),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: to),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: product),
                const SizedBox(width: 12),
                apply,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                grouping,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: from),
                    const SizedBox(width: 10),
                    Expanded(child: to),
                  ],
                ),
                const SizedBox(height: 12),
                product,
                const SizedBox(height: 12),
                apply,
              ],
            ),
    );
  }

  Widget _totalsTiles(double width) {
    final tiles = [
      (
        'Quantity sold',
        '${_totals['quantitySold']}',
        Icons.shopping_cart_outlined,
        const Color(0xFF2474E5),
      ),
      (
        'Delivered',
        _money(_totals['deliveredAmount']),
        Icons.task_alt_rounded,
        ShopColors.success,
      ),
      (
        'Pending',
        _money(_totals['pendingAmount']),
        Icons.hourglass_bottom_rounded,
        ShopColors.warning,
      ),
      (
        'Refund',
        _money(_totals['refundAmount']),
        Icons.undo_rounded,
        ShopColors.danger,
      ),
    ];
    final columns = width >= 900 ? 4 : 2;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: width >= 520 ? 96 : 120,
      ),
      children: [
        for (final (label, value, icon, color) in tiles)
          _MetricCard(title: label, value: value, icon: icon, color: color),
      ],
    );
  }

  Widget _table() => ShopPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: ShopColors.subtle,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: const Row(
            children: [
              Expanded(flex: 2, child: ShopTableHeading('DATE / PERIOD')),
              Expanded(flex: 4, child: ShopTableHeading('PRODUCT')),
              Expanded(
                flex: 2,
                child: ShopTableHeading('QTY SOLD', align: TextAlign.right),
              ),
              Expanded(
                flex: 3,
                child: ShopTableHeading('DELIVERED', align: TextAlign.right),
              ),
              Expanded(
                flex: 3,
                child: ShopTableHeading('PENDING', align: TextAlign.right),
              ),
              Expanded(
                flex: 3,
                child: ShopTableHeading('REFUND', align: TextAlign.right),
              ),
            ],
          ),
        ),
        for (final row in _rows) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '${row['sale_date']}',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    '${row['productName']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${row['quantitySold']}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _money(row['deliveredAmount']),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: ShopColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _money(row['pendingAmount']),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: ShopColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _money(row['refundAmount']),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: ShopColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _rowCard(Map<String, dynamic> row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ShopPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${row['productName']}  •  ${row['quantitySold']} sold',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${row['sale_date']} • delivered ${_money(row['deliveredAmount'])} • pending ${_money(row['pendingAmount'])} • refund ${_money(row['refundAmount'])}',
            style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gutter = shopGutter(width);
      final wide = width >= 900;
      return ListView(
        padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 28),
        children: [
          ShopContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _filters(wide),
                if (_busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_totals.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _totalsTiles(width - gutter * 2),
                ],
                const SizedBox(height: 18),
                if (_rows.isEmpty && !_busy)
                  const ShopPanel(
                    child: ShopEmptyState(
                      icon: Icons.query_stats_outlined,
                      message: 'No sales in this range.',
                      detail: 'Change the dates or grouping and apply again.',
                    ),
                  )
                else if (wide)
                  _table()
                else
                  for (final row in _rows) _rowCard(row),
              ],
            ),
          ),
        ],
      );
    },
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
  Widget build(BuildContext context) => ShopPanel(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
    final cancelled = text.toLowerCase().contains('cancel');
    final color = done
        ? const Color(0xFF138A63)
        : partial
        ? const Color(0xFFCC7A13)
        : cancelled
        ? const Color(0xFF64748B)
        : pending
        ? const Color(0xFFDC2626)
        : const Color(0xFF4775BA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.retry});
  final String error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5F5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF6C7C7)),
    ),
    child: ListTile(
      leading: const Icon(
        Icons.error_outline_rounded,
        color: ShopColors.danger,
      ),
      title: const Text('Could not load shop data'),
      subtitle: Text(error),
      trailing: IconButton(
        tooltip: 'Retry',
        onPressed: retry,
        icon: const Icon(Icons.refresh),
      ),
    ),
  );
}

/// Picture for an order line, chosen exactly like the customer catalogue
/// (ProductModel.displayImageUrl): order lines store the shared placeholder
/// photo name, which is shown as the product's own catalogue picture.
String _orderItemImage(Map<String, dynamic> item) => ProductModel.fromJson({
  'id': item['productId'] ?? item['id'],
  'name': item['name'],
  'sku': item['sku'],
  'category_key': item['categoryKey'],
  'img': item['image'],
}).displayImageUrl;

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _shopPaymentLabel(Map<String, dynamic> order) {
  final status = '${order['paymentStatus'] ?? 'pending'}'.toLowerCase();
  if (status == 'paid') return 'Paid';
  if (status == 'partially_paid') return 'Partially paid';
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
