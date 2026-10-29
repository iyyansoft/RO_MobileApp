import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/presentation/providers/product_provider.dart';
import '../../../products/domain/models/category_model.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../data/admin_repository.dart';
import '../../data/admin_files.dart';
import '../widgets/admin_product_fields.dart';
import 'bulk_products_screen.dart';

class AdminScreen extends ConsumerStatefulWidget {
  final AdminRepository? repository;
  const AdminScreen({super.key, this.repository});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  late final _repository = widget.repository ?? AdminRepository();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  static const _sections = [
    'Dashboard',
    'Dealers',
    'Products',
    'Categories',
    'Orders',
    'Settings',
    'Shop Employees',
  ];
  int _section = 0;
  bool _busy = false;
  String? _error;
  String _filter = 'All';
  String _period = 'daily';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _run(() async {
          if (await _repository.restoreSession()) await _load();
        });
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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

  Future<void> _load() async {
    final path = [
      'dashboard-stats',
      'dealers',
      'products',
      'categories',
      'orders',
      'session',
      'shop/employees',
    ][_section];
    final result = await _repository.request(path);
    if (_section == 0) {
      result['analytics'] = await _repository.request(
        'analytics?period=$_period',
      );
    }
    if (_section == 4) {
      final employees = await _repository.request('shop/employees');
      result['shopEmployees'] = employees['employees'] ?? const [];
    }
    if (mounted) setState(() => _data = result);
  }

  void _select(int section) {
    setState(() {
      _section = section;
      _data = {};
      _filter = 'All';
      _search.clear();
    });
    _run(_load);
  }

  Future<void> _mutate(
    String path,
    String method, [
    dynamic data,
  ]) => _run(() async {
    final result = await _repository.request(path, method: method, data: data);
    if (path.startsWith('products') || path.startsWith('categories')) {
      _refreshCatalog();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result['message'] ?? 'Saved successfully'}')),
      );
    }
    await _load();
  });

  void _refreshCatalog() {
    ref.invalidate(catalogProductsProvider);
    ref.invalidate(catalogCategoriesProvider);
  }

  Future<void> _addProduct() async {
    final bulk = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Add Product',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Single Product'),
              subtitle: const Text('Add an image, prices and product details'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_outlined),
              title: const Text('Bulk Products'),
              subtitle: const Text(
                'Enter multiple products and save them together',
              ),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (!mounted || bulk == null) return;
    if (!bulk) {
      await _edit({});
      return;
    }
    var categories = <CategoryModel>[];
    try {
      categories = await ref.read(catalogCategoriesProvider.future);
    } catch (_) {
      /* Allow category entry if lookup is unavailable. */
    }
    if (!mounted) return;
    final saved = await Navigator.of(context, rootNavigator: true).push<int>(
      MaterialPageRoute(
        builder: (context) => BulkProductsScreen(
          repository: _repository,
          categories: categories,
          onSaved: () {
            if (mounted) _refreshCatalog();
          },
        ),
      ),
    );
    if (!mounted) return;
    await _run(_load);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$saved products saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = _repository.token != null;
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF78B7FF) : const Color(0xFF2563EB);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: dark
            ? const Color(0xFF0C1422)
            : const Color(0xFFF3F6FC),
        colorScheme: base.colorScheme.copyWith(primary: accent),
        cardTheme: CardThemeData(
          elevation: 0,
          color: dark ? const Color(0xFF152033) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: dark ? Colors.white10 : const Color(0xFFE4EAF3),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xFF111B2C) : const Color(0xFFF7F9FD),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          constraints: const BoxConstraints(minHeight: 56),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: dark ? Colors.white10 : const Color(0xFFE4EAF3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !wide || !authenticated,
          leading: wide && authenticated && Navigator.canPop(context)
              ? const BackButton()
              : null,
          toolbarHeight: 76,
          backgroundColor: dark ? const Color(0xFF152033) : Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(
            authenticated ? _sections[_section] : 'RO Wholesale Admin',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          actions: authenticated
              ? [
                  IconButton(
                    onPressed: _busy ? null : () => _run(_load),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _repository.logout();
                            _data = {};
                          }),
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                  ),
                ]
              : null,
        ),
        drawer: authenticated && !wide
            ? Drawer(child: _navigation(closeDrawer: true))
            : null,
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(
              child: authenticated
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide) SizedBox(width: 250, child: _navigation()),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1440),
                              child: _content(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _login(),
            ),
          ],
        ),
        floatingActionButton: authenticated && (_section == 2 || _section == 3)
            ? FloatingActionButton.extended(
                onPressed: _busy
                    ? null
                    : _section == 2
                    ? _addProduct
                    : () => _edit({}),
                icon: const Icon(Icons.add),
                label: Text(_section == 2 ? 'Add Product' : 'Add category'),
              )
            : null,
      ),
    );
  }

  static const _sectionIcons = [
    Icons.space_dashboard_outlined,
    Icons.people_outline,
    Icons.inventory_2_outlined,
    Icons.category_outlined,
    Icons.receipt_long_outlined,
    Icons.settings_outlined,
    Icons.storefront_outlined,
  ];

  Widget _navigation({bool closeDrawer = false}) => Material(
    color: const Color(0xFF111E35),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 16, 10, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandLogo(width: 190, height: 68, onDark: true),
                SizedBox(height: 10),
                Text(
                  'Administration workspace',
                  style: TextStyle(color: Color(0xFF95A7C3), fontSize: 12),
                ),
              ],
            ),
          ),
          for (var index = 0; index < _sections.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                selectedTileColor: const Color(0xFF233C62),
                selected: index == _section,
                iconColor: const Color(0xFF95A7C3),
                textColor: const Color(0xFFB7C6DE),
                selectedColor: Colors.white,
                leading: Icon(_sectionIcons[index], size: 22),
                title: Text(
                  _sections[index],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  if (closeDrawer) Navigator.pop(context);
                  _select(index);
                },
              ),
            ),
        ],
      ),
    ),
  );

  Widget _login() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandLogo(width: 250, height: 90),
                const SizedBox(height: 24),
                const Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to manage your wholesale business.',
                  style: TextStyle(color: Color(0xFF718096), height: 1.5),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Admin email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text(
                    'Sign in to admin',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _signIn() {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your admin email and password.');
      return;
    }
    _run(() async {
      await _repository.login(_email.text, _password.text);
      await _load();
    });
  }

  Future<void> _createShopEmployee() async {
    final shopName = TextEditingController();
    final loginId = TextEditingController();
    final password = TextEditingController();
    String? validationError;
    final dialogRoute = DialogRoute<Map<String, String>>(
      context: context,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Shop Employee'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: shopName,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Shop name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loginId,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Login ID'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Password (minimum 10 characters)',
                  ),
                ),
                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      validationError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = shopName.text.trim();
                final id = loginId.text.trim();
                final secret = password.text;
                if (name.length < 2) {
                  setDialogState(() => validationError = 'Enter a shop name.');
                } else if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,31}$')
                    .hasMatch(id)) {
                  setDialogState(
                    () => validationError = 'Login ID must be 3–32 letters, numbers, dots, underscores, or hyphens.',
                  );
                } else if (secret.length < 10 || secret.length > 128) {
                  setDialogState(
                    () => validationError =
                        'Use a password between 10 and 128 characters.',
                  );
                } else {
                  Navigator.pop(dialogContext, {
                    'shopName': name,
                    'loginId': id,
                    'password': secret,
                  });
                }
              },
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
    final credentials = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(dialogRoute);
    // The push future resolves as soon as pop starts. Wait for the reverse
    // transition to remove the TextFields before disposing their controllers.
    await dialogRoute.completed;
    shopName.dispose();
    loginId.dispose();
    password.dispose();
    if (credentials == null || !mounted) return;
    await _run(() async {
      await _repository.request(
        'shop/employees',
        method: 'POST',
        data: credentials,
      );
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Employee account created'),
          content: SelectableText(
            'Shop: ${credentials['shopName']}\nLogin ID: ${credentials['loginId']}\n\nThe password was saved securely as a hash and is not returned by the server.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _recordShopRefund(Map<String, dynamic> notice) async {
    final reference = TextEditingController();
    final notes = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record refund - ${notice['order_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Refund amount: INR ${notice['refund_amount'] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Refund reference'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Refund notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark refunded'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      await _mutate('shop/orders/${notice['order_id']}/refund', 'PUT', {
        'status': 'refunded',
        'reference': reference.text.trim(),
        'notes': notes.text.trim(),
      });
    }
    reference.dispose();
    notes.dispose();
  }

  Widget _content() {
    if (_section == 0) return _dashboard();
    if (_section == 6) return _shopEmployees();
    if (_section == 5) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ListTile(
            leading: Icon(Icons.dns_outlined, color: Color(0xFF4D88E7)),
            title: Text('Backend connection'),
            subtitle: Text('API endpoint configured when building the app.'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(ApiClient.defaultBaseUrl),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF4D88E7),
            ),
            title: const Text('Signed in administrator'),
            subtitle: Text(
              '${(_data['admin'] as Map?)?['email'] ?? _email.text}',
            ),
          ),
        ],
      );
    }
    final key = ['', 'dealers', 'products', 'categories', 'orders'][_section];
    final rows = ((_data[key] as List?) ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          return jsonEncode(item)
                  .toLowerCase()
                  .contains(_search.text.toLowerCase()) &&
              (_filter == 'All' ||
                  '${item['status']}'.toLowerCase() == _filter.toLowerCase());
        })
        .toList();
    final statuses = _section == 1
        ? ['All', 'pending', 'approved', 'rejected']
        : _section == 2
        ? ['All', 'active', 'inactive']
        : _section == 4
        ? ['All', 'Pending', 'Partially Delivered', 'Delivered', 'Cancelled']
        : ['All'];
    return LayoutBuilder(
      builder: (_, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.62,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_sections[_section]} overview',
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Search, review and manage your records.',
                                style: TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${rows.length} records',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText:
                            'Search ${_sections[_section].toLowerCase()}',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (statuses.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final status in statuses)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text(status),
                                selected: _filter == status,
                                onSelected: (_) =>
                                    setState(() => _filter = status),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ExpansionTile(
                    title: const Text('Export records'),
                    children: [
                      TextButton.icon(
                        onPressed: _busy || rows.isEmpty
                            ? null
                            : () => _run(() async {
                                final saved = await AdminFiles.exportRows(
                                  'RO_${_sections[_section]}',
                                  rows,
                                );
                                if (mounted && saved) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Excel workbook saved.'),
                                    ),
                                  );
                                }
                              }),
                        icon: const Icon(Icons.download),
                        label: const Text('Export Excel'),
                      ),
                      TextButton.icon(
                        onPressed: rows.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: const JsonEncoder.withIndent('  ')
                                        .convert(rows),
                                  ),
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Filtered records copied as JSON.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy),
                        label: Text('Export ${rows.length} records as JSON'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _run(_load),
              child: rows.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            _busy ? 'Loading…' : 'No matching records.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: rows.length,
                      itemBuilder: (_, index) => _record(rows[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shopEmployees() {
    final employees = ((_data['employees'] as List?) ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shop team access',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Create a shop login ID and password. Passwords are stored as secure hashes.',
                    style: TextStyle(color: Color(0xFF718096)),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _createShopEmployee,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add employee'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (employees.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('No shop employees yet'),
              subtitle: Text(
                'Create an employee account to allow shop staff to sign in.',
              ),
            ),
          ),
        for (final employee in employees)
          Card(
            child: SwitchListTile(
              value: employee['active'] == true,
              onChanged: _busy
                  ? null
                  : (active) => _mutate(
                      'shop/employees/${employee['id']}/active',
                      'PUT',
                      {'active': active},
                    ),
              title: Text(
                '${employee['shop_name'] ?? employee['shopName'] ?? employee['full_name'] ?? 'Shop'}',
              ),
              subtitle: Text(
                'Login ID: ${employee['employee_id'] ?? employee['employeeId']} • ${employee['active'] == true ? 'Active' : 'Disabled'}',
              ),
              secondary: const CircleAvatar(child: Icon(Icons.badge_outlined)),
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'Partial delivery notices',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _repository.request('shop/notifications'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(title: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows = (snapshot.data!['notifications'] as List).map(
              (row) => Map<String, dynamic>.from(row as Map),
            );
            if (rows.isEmpty) {
              return const ListTile(
                title: Text('No partial delivery notices.'),
              );
            }
            return Column(
              children: [
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.local_shipping_outlined,
                        color: Color(0xFF2563EB),
                      ),
                      title: Text('${row['message']}'),
                      subtitle: Text(
                        'Refund pending review: ₹${row['refund_amount'] ?? 0} • ${row['employee_id'] ?? ''}',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _busy ? null : () => _recordShopRefund(row),
                        child: const Text('Record refund'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        const Text(
          'Product enquiries',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _repository.request('shop/enquiries'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(title: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows = (snapshot.data!['enquiries'] as List).map(
              (row) => Map<String, dynamic>.from(row as Map),
            );
            if (rows.isEmpty) {
              return const ListTile(
                title: Text('No product enquiries have been submitted.'),
              );
            }
            return Column(
              children: [
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.mark_email_unread_outlined),
                      title: Text(
                        '${row['product_name']} • Qty ${row['required_quantity']}',
                      ),
                      subtitle: Text(
                        '${row['customer_name']} / ${row['company_name']} • ${row['contact_number']}\n${row['category']} • ${row['status']}',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _dashboard() {
    final stats = Map<String, dynamic>.from((_data['stats'] as Map?) ?? {});
    final analytics = Map<String, dynamic>.from(
      (_data['analytics'] as Map?) ?? {},
    );
    final revenue = Map<String, dynamic>.from(
      (analytics['revenue'] as Map?) ?? {},
    );
    final metricCards = <({String label, String value, IconData icon})>[
      (
        label: 'Total products',
        value: '${stats['totalProducts'] ?? 0}',
        icon: Icons.inventory_2_outlined,
      ),
      (
        label: 'Active products',
        value: '${stats['activeProducts'] ?? 0}',
        icon: Icons.check_circle_outline_rounded,
      ),
      (
        label: 'Inactive products',
        value: '${stats['inactiveProducts'] ?? 0}',
        icon: Icons.pause_circle_outline_rounded,
      ),
      (
        label: 'Total orders',
        value: '${stats['totalOrders'] ?? 0}',
        icon: Icons.receipt_long_outlined,
      ),
      (
        label: 'Total dealers',
        value: '${stats['totalUsers'] ?? 0}',
        icon: Icons.people_outline_rounded,
      ),
      (
        label: 'Approved dealers',
        value: '${stats['approvedUsers'] ?? 0}',
        icon: Icons.verified_outlined,
      ),
      (
        label: 'Pending applications',
        value: '${stats['pendingUsers'] ?? 0}',
        icon: Icons.pending_actions_outlined,
      ),
      (
        label: 'Rejected applications',
        value: '${stats['rejectedUsers'] ?? 0}',
        icon: Icons.person_off_outlined,
      ),
      (
        label: 'Categories',
        value: '${stats['totalCategories'] ?? 0}',
        icon: Icons.category_outlined,
      ),
      (
        label: 'Today’s sales',
        value: _adminMoney(revenue['todayRevenue'] ?? 0),
        icon: Icons.today_outlined,
      ),
      (
        label: 'This month',
        value: _adminMoney(revenue['monthRevenue'] ?? 0),
        icon: Icons.calendar_month_outlined,
      ),
      (
        label: 'All order value',
        value: _adminMoney(stats['totalRevenue'] ?? 0),
        icon: Icons.account_balance_wallet_outlined,
      ),
      (
        label: 'Sales revenue',
        value: _adminMoney(
          revenue['totalRevenue'] ?? stats['totalRevenue'] ?? 0,
        ),
        icon: Icons.payments_outlined,
      ),
      (
        label: 'Sales orders',
        value: '${revenue['totalOrders'] ?? stats['totalOrders'] ?? 0}',
        icon: Icons.receipt_long_outlined,
      ),
      (
        label: 'Average order',
        value: _adminMoney(revenue['avgOrderValue'] ?? 0),
        icon: Icons.shopping_bag_outlined,
      ),
    ];
    final topProducts = (analytics['topProducts'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final lowStock = (analytics['lowStock'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF172D50), Color(0xFF245799)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.space_dashboard_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Business overview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Sales, products and dealer activity',
                      style: TextStyle(color: Color(0xFFCBDCF3), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _period.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >= 550
                ? 3
                : constraints.maxWidth >= 320
                ? 2
                : 1;
            const gap = 9.0;
            final width =
                (constraints.maxWidth - (columns - 1) * gap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metricCards)
                  SizedBox(
                    width: width,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 31,
                              height: 31,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                metric.icon,
                                color: const Color(0xFF3B72C4),
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metric.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF718096),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    metric.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
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
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Revenue performance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _period,
                isDense: true,
                items: ['daily', 'weekly', 'monthly']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (p) {
                        _period = p!;
                        _run(_load);
                      },
              ),
            ),
          ],
        ),
        if (analytics['chart'] is Map)
          ..._chart(Map<String, dynamic>.from(analytics['chart'] as Map)),
        const SizedBox(height: 14),
        _dashboardSectionTitle('Top selling products'),
        const SizedBox(height: 6),
        if (topProducts.isEmpty)
          _dashboardEmpty(
            'Sales data will appear here after orders are placed.',
          )
        else
          for (final item in topProducts) _dashboardProductCard(item),
        const SizedBox(height: 12),
        _dashboardSectionTitle('Low stock alerts'),
        const SizedBox(height: 6),
        if (lowStock.isEmpty)
          _dashboardEmpty('Your current inventory has no low stock alerts.')
        else
          for (final item in lowStock) _dashboardLowStockCard(item),
      ],
    );
  }

  Widget _dashboardSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );

  Widget _dashboardEmpty(String message) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF718096)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF718096), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dashboardProductCard(Map<String, dynamic> item) {
    final image = '${item['img'] ?? item['image'] ?? ''}'.trim();
    final name = '${item['name'] ?? item['productName'] ?? 'Product'}';
    final units =
        item['unitsSold'] ?? item['units_sold'] ?? item['quantity'] ?? 0;
    final totalRevenue = item['totalRevenue'] ?? item['revenue'] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _productImage(image, width: 52, height: 52, radius: 12),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$units units sold',
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _adminMoney(totalRevenue),
              style: const TextStyle(
                color: Color(0xFF176B52),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardLowStockCard(Map<String, dynamic> item) {
    final image = '${item['img'] ?? item['image'] ?? ''}'.trim();
    final name = '${item['name'] ?? 'Product'}';
    final stock = item['stock'] ?? item['stock_quantity'] ?? 0;
    final minimum = item['minStock'] ?? item['min_stock'] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _productImage(image, width: 46, height: 46, radius: 11),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item['sku'] ?? item['category'] ?? 'Inventory'}',
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$stock left · min $minimum',
                style: const TextStyle(
                  color: Color(0xFFAD5B00),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _chart(Map<String, dynamic> chart) {
    final labels = chart['labels'] as List? ?? [];
    final revenue = chart['revenueData'] as List? ?? [];
    final counts = chart['orderCountData'] as List? ?? [];
    final values = revenue
        .map((value) => num.tryParse('$value')?.toDouble() ?? 0.0)
        .toList();
    final maximum = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    return [
      Card(
        margin: const EdgeInsets.only(top: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 3),
          child: Column(
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${labels[i]}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            '₹${i < revenue.length ? revenue[i] : 0} · ${i < counts.length ? counts[i] : 0} orders',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: ((i < values.length ? values[i] : 0) / maximum)
                              .clamp(0.0, 1.0),
                          minHeight: 6,
                          color: const Color(0xFF4D88E7),
                          backgroundColor: const Color(0xFF4D88E7)
                              .withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _record(Map<String, dynamic> item) {
    if (_section == 2) return _productRecord(item);
    final title =
        '${item['name'] ?? item['title'] ?? item['orderId'] ?? item['id']}';
    final orderStatus =
        '${item['deliveryStatus'] ?? item['status'] ?? 'Pending'}';
    final statusColor = _section != 4
        ? const Color(0xFF2563EB)
        : orderStatus.toLowerCase().contains('partial')
        ? const Color(0xFFE08A16)
        : orderStatus.toLowerCase() == 'delivered'
        ? const Color(0xFF138A63)
        : const Color(0xFFDC2626);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.08),
          child: Icon(_sectionIcons[_section], color: statusColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          _section == 4
              ? '${item['userName'] ?? item['userEmail']} · ₹${item['grandTotal']} · ${item['status']}'
              : _section == 1
              ? '${item['business']} · ${item['status']}'
              : '${item['sku'] ?? item['key'] ?? ''} ${item['price'] != null ? '· ₹${item['price']}' : ''}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in item.entries)
                  if (![
                    'img',
                    'image',
                    'specs',
                    'features',
                    'items',
                  ].contains(entry.key))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: SelectableText('${entry.key}: ${entry.value}'),
                    ),
                if (item['items'] is List)
                  for (final line in item['items'] as List)
                    ListTile(
                      title: Text(
                        '${line['name'] ?? line['productName'] ?? 'Product'}',
                      ),
                      subtitle: Text(
                        _section == 4
                            ? 'Ordered: ${line['orderedQuantity'] ?? line['quantity'] ?? 0} | Delivered: ${line['actualDeliveredQuantity'] ?? 0} | Undelivered: ${line['undeliveredQuantity'] ?? 0}\nDealer price: ₹${line['dealerPrice'] ?? line['numericPrice'] ?? 0} | Delivered value: ₹${line['deliveredValue'] ?? 0} | Refund/adjustment: ₹${line['refundAmount'] ?? 0}'
                            : 'Quantity: ${line['quantity'] ?? line['qty']} | ₹${line['price']}',
                      ),
                    ),
                if (_section == 4) ...[
                  Text(
                    'Payment: ${item['paymentMethod'] ?? 'Unknown'} · ${item['paymentStatus'] ?? 'pending'} · Cash collected: ${item['cashCollected'] == true ? 'Yes' : 'No'}',
                    style: TextStyle(
                      color: item['cashCollected'] == true
                          ? const Color(0xFF16834A)
                          : const Color(0xFF687386),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item['cashCollected'] == true &&
                      item['cashCollectedAt'] != null)
                    Text(
                      'Cash collection confirmed: ${item['cashCollectedAt']} · ${item['cashCollectedBy'] ?? 'Employee unavailable'}',
                    ),
                  Text(
                    'Delivery status: ${item['deliveryStatus'] ?? item['status'] ?? 'Pending'}',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Delivered value: ₹${item['deliveredValue'] ?? 0} | Undelivered quantity: ${item['undeliveredQuantity'] ?? 0} | Refund/adjustment: ₹${item['refundAmount'] ?? 0}',
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: (() {
                      final shop = '${item['shopName'] ?? ''}';
                      final names = ((_data['shopEmployees'] as List?) ?? [])
                          .whereType<Map>()
                          .where((e) => e['active'] == true)
                          .map((e) => '${e['shop_name'] ?? ''}')
                          .where((n) => n.isNotEmpty)
                          .toSet();
                      return names.contains(shop) ? shop : '';
                    })(),
                    decoration: const InputDecoration(
                      labelText: 'Assigned shop',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Unassigned'),
                      ),
                      ...(((_data['shopEmployees'] as List?) ?? [])
                          .whereType<Map>()
                          .where((e) => e['active'] == true)
                          .map((e) => '${e['shop_name'] ?? ''}')
                          .where((n) => n.isNotEmpty)
                          .toSet()
                          .map(
                            (n) => DropdownMenuItem(value: n, child: Text(n)),
                          )),
                    ],
                    onChanged: _busy
                        ? null
                        : (name) {
                            if (name != null) {
                              _mutate(
                                'shop/orders/${Uri.encodeComponent('${item['orderId']}')}/assignment',
                                'PUT',
                                {'shopName': name},
                              );
                            }
                          },
                  ),
                ],
                Wrap(
                  spacing: 8,
                  children: [
                    if (_section == 1)
                      for (final status in ['approved', 'rejected', 'pending'])
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _mutate('set-status', 'POST', {
                                  'identifier': item['email'] ?? item['id'],
                                  'status': status,
                                }),
                          child: Text(status),
                        ),
                    if (_section == 4 && item['shopDeliveryStarted'] != true)
                      for (final status in [
                        'Processing & Dispatched',
                        'Delivered',
                        'Cancelled',
                      ])
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _mutate(
                                  'orders/${Uri.encodeComponent('${item['orderId']}')}/status',
                                  'PUT',
                                  {'status': status},
                                ),
                          child: Text(status),
                        ),
                    if (_section == 2 || _section == 3)
                      TextButton.icon(
                        onPressed: _busy ? null : () => _edit(item),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    if (_section != 4)
                      TextButton.icon(
                        onPressed: _busy ? null : () => _delete(item, title),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRecord(Map<String, dynamic> product) {
    final name = '${product['name'] ?? 'Untitled product'}';
    final price = product['price'] ?? product['dealer_price'] ?? 0;
    final mrp = product['mrp'] ?? price;
    final moq = product['moq'] ?? '1';
    final stock = product['stock_quantity'] ?? product['stock'] ?? 0;
    final image = '${product['img'] ?? product['image'] ?? ''}'.trim();
    final category = '${product['category'] ?? 'Uncategorized'}';
    final brand = '${product['brand'] ?? '—'}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showProductDetails(product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  _productImage(image, width: 68, height: 68, radius: 13),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SKU  ${product['sku'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF718096),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$category  ·  $brand',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF53657D),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 19),
              Row(
                children: [
                  Expanded(
                    child: _productListValue(
                      'Dealer price',
                      _adminMoney(price),
                      valueColor: const Color(0xFF1D4ED8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: _productListValue('MRP', _adminMoney(mrp))),
                  const SizedBox(width: 6),
                  Expanded(child: _productListValue('MOQ', '$moq')),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _productListValue(
                      'Stock',
                      '$stock',
                      valueColor: _stockColor(product, stock),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${product['status'] ?? 'active'}',
                      style: TextStyle(
                        color: _stockColor(product, stock),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _edit(product),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _delete(product, name),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productListValue(String label, String value, {Color? valueColor}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: Color(0xFF718096)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      );

  Widget _productImage(
    String source, {
    required double width,
    required double height,
    double radius = 18,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: const Color(0xFFF2F6FC),
      child: source.isEmpty
          ? SizedBox(
              width: width,
              height: height,
              child: const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFF8CA0B8),
              ),
            )
          : AppImage(
              source,
              width: width,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => SizedBox(
                width: width,
                height: height,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF8CA0B8),
                ),
              ),
            ),
    ),
  );

  Widget _productTag(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF2563EB).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF315A96),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Color _stockColor(Map<String, dynamic> product, dynamic stock) {
    final count = num.tryParse('$stock') ?? 0;
    if ('${product['status']}'.toLowerCase() == 'inactive' || count <= 0) {
      return const Color(0xFFDC2626);
    }
    final minimum = num.tryParse('${product['min_stock'] ?? 10}') ?? 10;
    return count <= minimum ? const Color(0xFFD97706) : const Color(0xFF059669);
  }

  String _adminMoney(dynamic value) {
    final amount = num.tryParse('$value') ?? 0;
    return '₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}';
  }

  Future<void> _showProductDetails(Map<String, dynamic> product) async {
    final name = '${product['name'] ?? 'Product details'}';
    final image = '${product['img'] ?? product['image'] ?? ''}'.trim();
    final price = product['price'] ?? product['dealer_price'] ?? 0;
    final stock = product['stock_quantity'] ?? product['stock'] ?? 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PRODUCT DETAILS',
                          style: TextStyle(
                            color: Color(0xFF718096),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop = constraints.maxWidth >= 620;
                      final gallery = _productImage(
                        image,
                        width: desktop ? 300 : constraints.maxWidth,
                        height: desktop ? 300 : 230,
                        radius: 20,
                      );
                      final summary = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _productTag('SKU  ${product['sku'] ?? '—'}'),
                              _productTag(
                                '${product['category'] ?? 'Uncategorized'}',
                              ),
                              _productTag('${product['brand'] ?? '—'}'),
                              _productTag('${product['status'] ?? 'active'}'),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _productMetric(
                                'Purchase price',
                                _adminMoney(
                                  product['purchase_price'] ??
                                      product['purchasePrice'] ??
                                      0,
                                ),
                              ),
                              _productMetric(
                                'Dealer price',
                                _adminMoney(price),
                                emphasize: true,
                              ),
                              _productMetric(
                                'MRP',
                                _adminMoney(product['mrp'] ?? price),
                              ),
                              _productMetric(
                                'Minimum order',
                                '${product['moq'] ?? '1'}',
                              ),
                              _productMetric(
                                'Stock',
                                '$stock units',
                                valueColor: _stockColor(product, stock),
                              ),
                              _productMetric(
                                'Rating',
                                '${product['rating'] ?? '—'}',
                              ),
                            ],
                          ),
                        ],
                      );
                      if (desktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 300, height: 300, child: gallery),
                            const SizedBox(width: 24),
                            Expanded(child: summary),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          gallery,
                          const SizedBox(height: 20),
                          summary,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Description',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${product['desc'] ?? product['description'] ?? 'No product description has been added.'}',
                    style: const TextStyle(
                      height: 1.55,
                      color: Color(0xFF58677D),
                    ),
                  ),
                  if (product['specs'] is Map &&
                      (product['specs'] as Map).isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Specifications',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in (product['specs'] as Map).entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text('${entry.key}: ${entry.value}'),
                      ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(dialogContext);
                                _edit(product);
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit product'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(dialogContext);
                                _delete(product, name);
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete product'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productMetric(
    String label,
    String value, {
    Color? valueColor,
    bool emphasize = false,
  }) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: emphasize
          ? const Color(0xFF2563EB).withValues(alpha: 0.08)
          : const Color(0xFFF4F7FB),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF718096), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: valueColor ?? (emphasize ? const Color(0xFF1D4ED8) : null),
          ),
        ),
      ],
    ),
  );

  Future<void> _delete(Map<String, dynamic> item, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          _section == 3
              ? 'Products in this category will be reassigned to Spares.'
              : 'This record will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _mutate(
        '${_section == 1
            ? 'users'
            : _section == 2
            ? 'products'
            : 'categories'}/${Uri.encodeComponent('${item['id']}')}',
        'DELETE',
      );
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final product = _section == 2;
    final fields = product
        ? [
            'name',
            'sku',
            'category',
            'brand',
            'purchase_price',
            'price',
            'mrp',
            'moq',
            'stock_quantity',
            'min_stock',
            'rating',
            'img',
            'desc',
            'specs',
            'features',
            'badge',
            'status',
          ]
        : ['name', 'key', 'image', 'description'];
    final defaults = {
      'status': 'active',
      'moq': '1 Piece',
      'stock_quantity': 50,
      'min_stock': 10,
      'purchase_price': 0,
      'rating': 0,
      'mrp': item['price'] ?? 0,
      'specs': <String, dynamic>{},
      'features': <String>[],
      'key': item['key_name'] ?? '',
      'image': item['image_url'] ?? item['img'] ?? '',
    };
    final controllers = {
      for (final field in fields)
        field: TextEditingController(
          text: ['specs', 'features'].contains(field)
              ? jsonEncode(item[field] ?? defaults[field])
              : '${item[field] ?? (field == 'name' ? item['title'] : null) ?? defaults[field] ?? ''}',
        ),
    };
    final form = GlobalKey<FormState>();
    var categories = <CategoryModel>[];
    if (product) {
      try {
        categories = await ref.read(catalogCategoriesProvider.future);
      } catch (_) {
        /* Allow manual category entry if category lookup fails. */
      }
    }
    if (!mounted) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
      builder: (context) => AlertDialog(
        title: Text(
          '${item.isEmpty ? 'Add' : 'Edit'} ${product ? 'product' : 'category'}',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final image = await AdminFiles.pickImage();
                        if (image != null) {
                          controllers[product ? 'img' : 'image']!.text = image;
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text(
                      'Upload image (JPG, PNG, WebP · up to 5 MB)',
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        controllers[product ? 'img' : 'image']!.clear(),
                    child: const Text('Remove image'),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controllers[product ? 'img' : 'image']!,
                    builder: (_, value, __) {
                      final source = value.text.trim();
                      if (source.isEmpty) return const SizedBox.shrink();
                      try {
                        return Container(
                          height: 150,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F6FC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: AppImage(
                            source,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Text('Image preview unavailable'),
                            ),
                          ),
                        );
                      } catch (_) {
                        return const Text('Image preview unavailable');
                      }
                    },
                  ),
                  if (product)
                    AdminProductFields(
                      controllers: controllers,
                      categories: categories,
                    ),
                  for (final field in product ? <String>[] : fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[field],
                        maxLines:
                            [
                              'desc',
                              'description',
                              'specs',
                              'features',
                            ].contains(field)
                            ? 3
                            : 1,
                        decoration: InputDecoration(
                          labelText: ['specs', 'features'].contains(field)
                              ? '$field (JSON)'
                              : field,
                        ),
                        validator: (value) {
                          if ([
                                'name',
                                'sku',
                                'category',
                                'key',
                                'price',
                              ].contains(field) &&
                              (value ?? '').trim().isEmpty) {
                            return 'Required';
                          }
                          if ([
                                'price',
                                'mrp',
                                'purchase_price',
                                'stock_quantity',
                                'min_stock',
                              ].contains(field) &&
                              num.tryParse(value ?? '') == null) {
                            return 'Enter a number';
                          }
                          if (['specs', 'features'].contains(field)) {
                            try {
                              final decoded = jsonDecode(value!);
                              if (field == 'specs'
                                  ? decoded is! Map
                                  : decoded is! List) {
                                return 'Invalid JSON type';
                              }
                            } catch (_) {
                              return 'Enter valid JSON';
                            }
                          }
                          if (field == 'status' &&
                              !['active', 'inactive'].contains(value)) {
                            return 'Use active or inactive';
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final result = <String, dynamic>{...item};
              for (final field in fields) {
                final value = controllers[field]!.text.trim();
                result[field] = ['specs', 'features'].contains(field)
                    ? jsonDecode(value)
                    : [
                        'price',
                        'mrp',
                        'purchase_price',
                        'stock_quantity',
                        'min_stock',
                      ].contains(field)
                    ? num.parse(value)
                    : value;
              }
              Navigator.pop(context, result);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final payload = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (payload != null) {
      await _mutate(
        '${product ? 'products' : 'categories'}${item.isEmpty ? '' : '/${Uri.encodeComponent('${item['id']}')}'}',
        item.isEmpty ? 'POST' : 'PUT',
        payload,
      );
    }
  }
}
