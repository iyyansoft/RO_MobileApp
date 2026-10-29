import 'dart:convert';
import 'dart:html' as html;

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_config.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_files.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const AdminWebApp());
}

const _ink = Color(0xFF102A43);
const _blue = Color(0xFF1769FF);
const _canvas = Color(0xFFF4F7FB);

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RO Wholesale Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      fontFamily: 'Arial',
      inputDecorationTheme: const InputDecorationTheme(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        constraints: BoxConstraints(minHeight: 56),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8EDF4)),
        ),
      ),
    ),
    home: const AdminGate(),
  );
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  final repo = AdminRepository();
  bool loading = true;
  bool signedIn = false;

  @override
  void initState() {
    super.initState();
    repo
        .restoreSession()
        .then((value) {
          if (mounted) {
            setState(() {
              signedIn = value;
              loading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(() {
              signedIn = false;
              loading = false;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return signedIn
        ? AdminDashboard(
            repo: repo,
            onLogout: () => setState(() => signedIn = false),
          )
        : AdminLogin(
            repo: repo,
            onLogin: () => setState(() => signedIn = true),
          );
  }
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({required this.repo, required this.onLogin, super.key});
  final AdminRepository repo;
  final VoidCallback onLogin;
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repo.login(email.text, password.text);
      widget.onLogin();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        if (MediaQuery.sizeOf(context).width > 760)
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_ink, Color(0xFF174D82)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(64),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BrandLogo(width: 250, height: 90, onDark: true),
                  SizedBox(height: 28),
                  Text(
                    'Your business,\nat a glance.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Manage dealers, products, orders and performance from one workspace.',
                    style: TextStyle(
                      color: Color(0xFFCEE0F7),
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          flex: 4,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (MediaQuery.sizeOf(context).width <= 760)
                      const Center(child: BrandLogo(width: 250, height: 90)),
                    const Text(
                      'Admin sign in',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use your administrator credentials to continue.',
                      style: TextStyle(color: Color(0xFF63758A)),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Email address',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.email_outlined),
                        hintText: 'admin@example.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Password',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: password,
                      obscureText: obscure,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in'),
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
  );
}

const _sections = [
  ('Overview', Icons.space_dashboard_outlined),
  ('Dealer Approval', Icons.verified_user_outlined),
  ('Products', Icons.inventory_2_outlined),
  ('Categories', Icons.category_outlined),
  ('Stock Management', Icons.warehouse_outlined),
  ('Orders', Icons.shopping_bag_outlined),
  ('Payments', Icons.account_balance_wallet_outlined),
  ('Invoices', Icons.receipt_long_outlined),
  ('Reports', Icons.bar_chart_outlined),
];

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({required this.repo, required this.onLogout, super.key});
  final AdminRepository repo;
  final VoidCallback onLogout;
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int selected = 0;
  bool loading = true;
  String? error;
  Map<String, dynamic> stats = {}, analytics = {};
  List<Map<String, dynamic>> dealers = [],
      products = [],
      categories = [],
      orders = [],
      shopEmployees = [];
  int productMode = 0;
  String? importFilename;
  String? importError;
  bool importing = false;
  List<_ImportProduct> importRows = [];
  DateTime reportDate = DateTime.now();
  DateTimeRange? reportRange;
  String reportPeriod = 'daily';
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        widget.repo.request('dashboard-stats'),
        widget.repo.request('analytics'),
        widget.repo.request('dealers'),
        widget.repo.request('products'),
        widget.repo.request('categories'),
        widget.repo.request('orders'),
      ]);
      List<Map<String, dynamic>> employeeRows = [];
      try {
        employeeRows = _rows(
          (await widget.repo.request('shop/employees'))['employees'],
        );
      } catch (_) {
        // Shop employee setup is optional for the rest of the admin dashboard.
      }
      if (!mounted) return;
      setState(() {
        stats = _map(results[0]['stats']);
        analytics = results[1];
        dealers = _rows(results[2]['dealers']);
        products = _rows(results[3]['products']);
        categories = _rows(results[4]['categories']);
        orders = _rows(results[5]['orders']);
        shopEmployees = employeeRows;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> updateDealer(Map<String, dynamic> dealer, String status) async {
    try {
      await widget.repo.request(
        'set-status',
        method: 'POST',
        data: {
          'identifier': '${dealer['id'] ?? dealer['email'] ?? ''}',
          'status': status,
        },
      );
      await refresh();
      if (mounted) _notice('$status dealer');
    } catch (e) {
      if (mounted) _notice(e.toString(), isError: true);
    }
  }

  Future<void> updateOrder(Map<String, dynamic> order, String status) async {
    try {
      await widget.repo.request(
        'orders/${Uri.encodeComponent('${order['orderId'] ?? order['id'] ?? ''}')}/status',
        method: 'PUT',
        data: {'status': status},
      );
      await refresh();
    } catch (e) {
      if (mounted) _notice(e.toString(), isError: true);
    }
  }

  Future<void> assignOrderToShop(
    Map<String, dynamic> order,
    String shopName,
  ) async {
    try {
      await widget.repo.request(
        'shop/orders/${Uri.encodeComponent('${order['orderId'] ?? order['id'] ?? ''}')}/assignment',
        method: 'PUT',
        data: {'shopName': shopName},
      );
      await refresh();
      if (mounted) {
        _notice(
          shopName.isEmpty
              ? 'Shop assignment removed'
              : 'Order assigned to $shopName',
        );
      }
    } catch (e) {
      if (mounted) _notice(e.toString(), isError: true);
    }
  }

  Future<void> _showSingleProductForm({Map<String, dynamic>? product}) async {
    final formKey = GlobalKey<FormState>();
    final fields = {
      'name': TextEditingController(text: '${product?['name'] ?? ''}'),
      'sku': TextEditingController(text: '${product?['sku'] ?? ''}'),
      'brand': TextEditingController(
        text: '${product?['brand'] ?? 'RO Wholesale'}',
      ),
      'purchase': TextEditingController(
        text: '${product?['purchase_price'] ?? product?['purchasePrice'] ?? 0}',
      ),
      'dealer': TextEditingController(text: '${product?['price'] ?? ''}'),
      'mrp': TextEditingController(text: '${product?['mrp'] ?? ''}'),
      'moq': TextEditingController(
        text: '${product?['moq'] ?? '1'}'.replaceFirst('MOQ:', '').trim(),
      ),
      'stock': TextEditingController(
        text: '${product?['stock_quantity'] ?? product?['stock'] ?? 50}',
      ),
      'description': TextEditingController(
        text: '${product?['desc'] ?? product?['description'] ?? ''}',
      ),
    };
    var imageValue = '${product?['img'] ?? product?['image'] ?? ''}';
    final currentCategory = '${product?['category'] ?? ''}';
    var category = categories.isEmpty
        ? (currentCategory.isEmpty ? null : currentCategory)
        : categories
              .map(_categoryKey)
              .firstWhere(
                (key) => key.toLowerCase() == currentCategory.toLowerCase(),
                orElse: () => _categoryKey(categories.first),
              );
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(product == null ? 'Add single product' : 'Edit product'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    Widget input(
                      String key,
                      String label, {
                      bool required = false,
                      TextInputType? keyboard,
                    }) => TextFormField(
                      controller: fields[key],
                      keyboardType: keyboard,
                      decoration: InputDecoration(
                        labelText: label,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          required && (value == null || value.trim().isEmpty)
                          ? 'Required'
                          : null,
                    );
                    Widget row(List<Widget> children) => Row(
                      children: children
                          .expand(
                            (child) => [
                              Expanded(child: child),
                              if (child != children.last)
                                const SizedBox(width: 12),
                            ],
                          )
                          .toList(),
                    );
                    return Column(
                      children: [
                        input('name', 'Product name', required: true),
                        const SizedBox(height: 16),
                        row([
                          input('sku', 'SKU', required: true),
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: _categoryKey(c),
                                    child: Text(
                                      '${c['title'] ?? c['name'] ?? _categoryKey(c)}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => category = value,
                            validator: (value) =>
                                value == null ? 'Choose a category' : null,
                          ),
                        ]),
                        const SizedBox(height: 16),
                        input('brand', 'Brand'),
                        const SizedBox(height: 16),
                        _AdminImagePicker(
                          value: imageValue,
                          onChanged: (value) =>
                              setDialogState(() => imageValue = value ?? ''),
                        ),
                        const SizedBox(height: 16),
                        row([
                          input(
                            'purchase',
                            'Purchase price',
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          input(
                            'dealer',
                            'Dealer price',
                            required: true,
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        row([
                          input(
                            'mrp',
                            'MRP',
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          input('moq', 'MOQ', keyboard: TextInputType.number),
                        ]),
                        const SizedBox(height: 16),
                        input('stock', 'Stock', keyboard: TextInputType.number),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: fields['description'],
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final price = _number(fields['dealer']!.text);
                      final stock = int.tryParse(fields['stock']!.text.trim());
                      if (price == null ||
                          price <= 0 ||
                          stock == null ||
                          stock < 0) {
                        _notice(
                          'Enter a valid dealer price and nonnegative stock.',
                          isError: true,
                        );
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await widget.repo.request(
                          product == null
                              ? 'products'
                              : 'products/${Uri.encodeComponent('${product['sku'] ?? product['id']}')}',
                          method: product == null ? 'POST' : 'PUT',
                          data: {
                            'name': fields['name']!.text.trim(),
                            'sku': fields['sku']!.text.trim(),
                            'category': category,
                            'brand': fields['brand']!.text.trim(),
                            'img': imageValue,
                            'purchase_price':
                                _number(fields['purchase']!.text) ?? 0,
                            'price': price,
                            'mrp': _number(fields['mrp']!.text) ?? price * 1.25,
                            'moq': fields['moq']!.text.trim().isEmpty
                                ? '1'
                                : fields['moq']!.text.trim(),
                            'stock_quantity': stock,
                            'desc': fields['description']!.text.trim(),
                            if (product?['badge'] != null)
                              'badge': product!['badge'],
                            if (product?['rating'] != null)
                              'rating': product!['rating'],
                            if (product?['specs'] != null)
                              'specs': product!['specs'],
                            if (product?['features'] != null)
                              'features': product!['features'],
                            if (product?['applications'] != null)
                              'applications': product!['applications'],
                            if (product?['status'] != null)
                              'status': product!['status'],
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await refresh();
                        if (mounted) _notice('Product saved.');
                      } catch (e) {
                        if (mounted) _notice(e.toString(), isError: true);
                      } finally {
                        if (dialogContext.mounted)
                          setDialogState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(product == null ? 'Save product' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    for (final controller in fields.values) {
      controller.dispose();
    }
  }

  Future<void> _showCategoryForm({Map<String, dynamic>? category}) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(
      text: '${category?['title'] ?? category?['name'] ?? ''}',
    );
    final key = TextEditingController(
      text: '${category?['key_name'] ?? category?['key'] ?? ''}',
    );
    final description = TextEditingController(
      text: '${category?['description'] ?? ''}',
    );
    final order = TextEditingController(
      text: '${category?['display_order'] ?? categories.length + 1}',
    );
    final badge = TextEditingController(
      text: '${category?['badge_text'] ?? 'B2B WHOLESALE'}',
    );
    final color = TextEditingController(
      text: '${category?['icon_color'] ?? '#1769FF'}',
    );
    var imageValue =
        '${category?['image_url'] ?? category?['image'] ?? category?['img'] ?? ''}';
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? 'Add category' : 'Edit category'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'Category name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: key,
                      decoration: const InputDecoration(
                        labelText: 'Category key',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: order,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Display order',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => int.tryParse(v ?? '') == null
                                ? 'Enter a number'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: color,
                            decoration: const InputDecoration(
                              labelText: 'Icon color',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: badge,
                      decoration: const InputDecoration(
                        labelText: 'Badge text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AdminImagePicker(
                      value: imageValue,
                      onChanged: (value) =>
                          setDialogState(() => imageValue = value ?? ''),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => busy = true);
                      try {
                        final payload = {
                          'title': title.text.trim(),
                          'key_name': key.text.trim().toLowerCase().replaceAll(
                            RegExp(r'\s+'),
                            '_',
                          ),
                          'description': description.text.trim(),
                          'display_order': int.parse(order.text),
                          'badge_text': badge.text.trim(),
                          'icon_color': color.text.trim(),
                          'image_url': imageValue,
                        };
                        final id =
                            '${category?['id'] ?? category?['key_name'] ?? category?['key'] ?? ''}';
                        await widget.repo.request(
                          category == null
                              ? 'categories'
                              : 'categories/${Uri.encodeComponent(id)}',
                          method: category == null ? 'POST' : 'PUT',
                          data: payload,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await refresh();
                        if (mounted)
                          _notice(
                            category == null
                                ? 'Category added.'
                                : 'Category updated.',
                          );
                      } catch (e) {
                        if (mounted) _notice(e.toString(), isError: true);
                      } finally {
                        if (dialogContext.mounted)
                          setDialogState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(category == null ? 'Add category' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [title, key, description, order, badge, color]) {
      controller.dispose();
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete “${category['title'] ?? category['name'] ?? ''}”? Existing products will be moved to the fallback category by the current API.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id =
          '${category['id'] ?? category['key_name'] ?? category['key'] ?? ''}';
      await widget.repo.request(
        'categories/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      );
      await refresh();
      if (mounted) _notice('Category deleted.');
    } catch (e) {
      if (mounted) _notice(e.toString(), isError: true);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Delete “${product['name'] ?? ''}” from the catalog?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = '${product['id'] ?? product['sku'] ?? ''}';
      await widget.repo.request(
        'products/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      );
      await refresh();
      if (mounted) _notice('Product deleted.');
    } catch (e) {
      if (mounted) _notice(e.toString(), isError: true);
    }
  }

  Future<void> _pickBulkFile() async {
    setState(() {
      importError = null;
      importRows = [];
      importFilename = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty)
        throw const FormatException(
          'The selected file is empty or could not be read.',
        );
      final extension = file.extension?.toLowerCase();
      final table = extension == 'csv'
          ? _parseCsv(utf8.decode(bytes, allowMalformed: true))
          : _parseWorkbook(bytes);
      final parsed = _validateImportTable(table);
      if (!mounted) return;
      setState(() {
        importFilename = file.name;
        importRows = parsed.rows;
        importError = parsed.error;
      });
    } catch (e) {
      if (mounted) setState(() => importError = 'Could not read this file: $e');
    }
  }

  void _downloadBulkProductTemplate({required bool asExcel}) {
    final headers = AdminFiles.productHeaders;
    if (asExcel) {
      final workbook = Excel.createExcel();
      final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
      sheet.appendRow(headers.map(TextCellValue.new).toList());
      final bytes = workbook.encode();
      if (bytes == null) {
        _notice('Excel template could not be generated.', isError: true);
        return;
      }
      _saveBrowserFile(
        'ro_bulk_products_template.xlsx',
        bytes,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } else {
      final csv = '${headers.map(_csvEscape).join(',')}\r\n';
      _saveBrowserFile(
        'ro_bulk_products_template.csv',
        utf8.encode('\uFEFF$csv'),
        'text/csv;charset=utf-8',
      );
    }
    _notice('${asExcel ? 'Excel' : 'CSV'} product template downloaded.');
  }

  Future<void> _importBulkProducts() async {
    final validRows = importRows.where((row) => row.errors.isEmpty).toList();
    if (validRows.isEmpty) return;
    setState(() {
      importing = true;
      importError = null;
    });
    try {
      final result = await widget.repo.request(
        'products/bulk',
        method: 'POST',
        data: {'products': validRows.map((row) => row.product).toList()},
      );
      final skipped = _rows(result['skipped']);
      final importedSkus = _rows(result['imported'])
          .map((row) => '${row['sku'] ?? ''}'.toUpperCase())
          .toSet();
      final skippedBySku = <String, String>{
        for (final row in skipped)
          '${row['sku'] ?? ''}'.toUpperCase(): '${row['reason'] ?? 'Skipped'}',
      };
      final detail = skipped.isEmpty
          ? ''
          : ' ${skipped.length} row(s) were skipped.';
      if (mounted)
        _notice(
          result['replayed'] == true
              ? 'This exact batch was already processed. No duplicate products were added.$detail'
              : '${result['importedCount'] ?? 0} product(s) imported.$detail',
        );
      if (mounted) {
        setState(() {
          importRows = importRows
              .where(
                (row) => !importedSkus.contains(
                  '${row.product['sku'] ?? ''}'.toUpperCase(),
                ),
              )
              .map((row) {
                final reason =
                    skippedBySku['${row.product['sku'] ?? ''}'.toUpperCase()];
                return reason == null
                    ? row
                    : _ImportProduct(row.rowNumber, row.product, [
                        ...row.errors,
                        reason,
                      ]);
              })
              .toList();
          importError = skipped.isEmpty
              ? null
              : skipped
                    .map(
                      (row) =>
                          'SKU ${row['sku'] ?? ''}: ${row['reason'] ?? 'Skipped'}',
                    )
                    .join('\n');
          if (importRows.isEmpty) importFilename = null;
        });
      }
      await refresh();
    } catch (e) {
      if (mounted) setState(() => importError = e.toString());
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  _ImportParseResult _validateImportTable(List<List<String>> table) {
    final nonEmpty = table
        .asMap()
        .entries
        .where((entry) => entry.value.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (nonEmpty.length < 2)
      return const _ImportParseResult(
        [],
        'The file needs a header row and at least one product row.',
      );
    final headers = nonEmpty.first.value.map(_headerKey).toList();
    int column(List<String> names) => headers.indexWhere(names.contains);
    final nameCol = column([
      'name',
      'productname',
      'product',
      'productdetails',
    ]);
    final skuCol = column(['sku', 'skucode', 'productcode']);
    final priceCol = column(['dealerprice', 'price', 'sellingprice']);
    if (nameCol < 0 || skuCol < 0 || priceCol < 0)
      return const _ImportParseResult(
        [],
        'Required columns: Name, SKU, and Dealer Price.',
      );
    final duplicateHeaders = <String>{};
    final seenHeaders = <String>{};
    for (final header in headers.where((header) => header.isNotEmpty)) {
      if (!seenHeaders.add(header)) duplicateHeaders.add(header);
    }
    if (duplicateHeaders.isNotEmpty) {
      return _ImportParseResult(
        [],
        'The file contains duplicate columns: ${duplicateHeaders.join(', ')}.',
      );
    }
    final existingSkus = products
        .map((p) => '${p['sku'] ?? ''}'.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final seen = <String>{};
    final parsed = <_ImportProduct>[];
    for (var rowIndex = 1; rowIndex < nonEmpty.length; rowIndex++) {
      final source = nonEmpty[rowIndex].value;
      String value(List<String> aliases) {
        final index = column(aliases);
        return index < 0 || index >= source.length ? '' : source[index].trim();
      }

      final name = value(['name', 'productname', 'product', 'productdetails']);
      final sku = value(['sku', 'skucode', 'productcode']).toUpperCase();
      final categoryInput = value([
        'category',
        'categoryname',
        'categoryid',
        'categorykey',
      ]);
      final category = _resolveCategory(categoryInput);
      final brand = value(['brand']);
      final dealer = _number(value(['dealerprice', 'price', 'sellingprice']));
      final purchaseText = value(['purchaseprice', 'purchase']);
      final purchase = purchaseText.isEmpty ? 0.0 : _number(purchaseText);
      final mrpText = value(['mrp', 'listprice']);
      final mrp = mrpText.isEmpty
          ? (dealer == null ? null : dealer * 1.25)
          : _number(mrpText);
      final moqText = value(['moq', 'minimumorderquantity']);
      final stockText = value(['stock', 'stockquantity', 'quantity']);
      final moqMatch = RegExp(
        r'^(?:MOQ\s*:\s*)?(\d+)(?:\s*(?:unit|units|pcs|pieces))?$',
        caseSensitive: false,
      ).firstMatch(moqText);
      final moq = moqText.isEmpty
          ? 1
          : int.tryParse(moqText) ?? int.tryParse(moqMatch?.group(1) ?? '');
      final stock = stockText.isEmpty ? 50 : int.tryParse(stockText);
      final errors = <String>[];
      if (name.isEmpty) errors.add('Name is required.');
      if (sku.isEmpty) errors.add('SKU is required.');
      if (sku.isNotEmpty &&
          !RegExp(r'^[A-Z0-9][A-Z0-9._/-]{0,63}$').hasMatch(sku)) {
        errors.add(
          'SKU must use letters, numbers, dot, underscore, slash or hyphen.',
        );
      }
      if (categoryInput.isEmpty)
        errors.add('Category is required.');
      else if (category == null)
        errors.add('Category does not match an existing category.');
      if (dealer == null || dealer <= 0 || dealer > 99999999.99)
        errors.add(
          'Dealer Price must be greater than 0 and fit the catalog price limit.',
        );
      if (purchase == null || purchase < 0 || purchase > 99999999.99)
        errors.add('Purchase Price must be a valid nonnegative amount.');
      if (mrp == null || mrp <= 0 || mrp > 99999999.99)
        errors.add('MRP must be a valid positive amount.');
      if (moq == null || moq < 1)
        errors.add('MOQ must be a positive whole number.');
      if (stock == null || stock < 0 || stock > 2147483647)
        errors.add('Stock must be a nonnegative whole number.');
      if (sku.isNotEmpty && existingSkus.contains(sku))
        errors.add('SKU already exists in the catalog.');
      if (sku.isNotEmpty && !seen.add(sku))
        errors.add('SKU is duplicated in this file.');
      final product = <String, dynamic>{
        'name': name,
        'sku': sku,
        'category': category ?? categoryInput,
        'brand': brand.isEmpty ? 'RO Wholesale' : brand,
        'purchase_price': purchase ?? 0,
        'price': dealer ?? 0,
        'mrp': mrp ?? 0,
        'moq': moq ?? 1,
        'stock_quantity': stock ?? 50,
        'desc': value(['productdescription', 'description', 'desc']),
        'img': value(['image', 'imageurl', 'img']),
      };
      parsed.add(_ImportProduct(nonEmpty[rowIndex].key + 1, product, errors));
    }
    return _ImportParseResult(parsed, null);
  }

  String? _resolveCategory(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return null;
    for (final category in categories) {
      final key = _categoryKey(category).toLowerCase();
      final id = '${category['id'] ?? ''}'.trim().toLowerCase();
      final title = '${category['title'] ?? category['name'] ?? ''}'
          .trim()
          .toLowerCase();
      if (query == key || query == id || query == title)
        return _categoryKey(category);
    }
    return null;
  }

  Future<void> _pickReportDate({bool range = false}) async {
    if (range) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2018),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: reportRange,
      );
      if (picked != null) setState(() => reportRange = picked);
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: reportDate,
        firstDate: DateTime(2018),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) setState(() => reportDate = picked);
    }
  }

  List<Map<String, dynamic>> _filteredReportOrders(String period) {
    late DateTime start;
    late DateTime endExclusive;
    if (period == 'daily') {
      start = DateTime(reportDate.year, reportDate.month, reportDate.day);
      endExclusive = start.add(const Duration(days: 1));
    } else if (period == 'monthly') {
      start = DateTime(reportDate.year, reportDate.month);
      endExclusive = DateTime(reportDate.year, reportDate.month + 1);
    } else {
      final range = reportRange;
      if (range == null) return [];
      start = DateTime(range.start.year, range.start.month, range.start.day);
      endExclusive = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1));
    }
    return orders.where((order) {
      final date = DateTime.tryParse('${order['createdAt'] ?? ''}')?.toLocal();
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(start) && day.isBefore(endExclusive);
    }).toList();
  }

  Future<void> _downloadReport(String period, {required bool asExcel}) async {
    if (period == 'custom' && reportRange == null) {
      _notice('Choose a date range first.', isError: true);
      return;
    }
    setState(() => exporting = true);
    try {
      final rows = _filteredReportOrders(period);
      const headers = [
        'Order ID',
        'Order Date',
        'Dealer',
        'Email',
        'Payment Method',
        'Status',
        'Subtotal',
        'Discount',
        'GST',
        'Delivery Fee',
        'Total',
        'Invoice Number',
        'Line Items',
      ];
      final values = rows
          .map(
            (order) => [
              '${order['orderId'] ?? order['id'] ?? ''}',
              '${order['createdAt'] ?? ''}',
              '${order['userName'] ?? ''}',
              '${order['userEmail'] ?? ''}',
              '${order['paymentMethod'] ?? ''}',
              '${order['status'] ?? ''}',
              '${order['subtotal'] ?? 0}',
              '${order['discount'] ?? 0}',
              '${order['gst'] ?? 0}',
              '${order['deliveryFee'] ?? 0}',
              '${order['grandTotal'] ?? order['total'] ?? 0}',
              '${order['invoiceNumber'] ?? ''}',
              '${(order['items'] as List? ?? []).length}',
            ],
          )
          .toList();
      final suffix = period == 'daily'
          ? _dateFilePart(reportDate)
          : period == 'monthly'
          ? '${reportDate.year}-${reportDate.month.toString().padLeft(2, '0')}'
          : '${_dateFilePart(reportRange!.start)}_to_${_dateFilePart(reportRange!.end)}';
      final filename = 'ro_orders_${period}_$suffix';
      if (asExcel) {
        final workbook = Excel.createExcel();
        final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
        sheet.appendRow(headers.map(TextCellValue.new).toList());
        for (final row in values) {
          sheet.appendRow(row.map(TextCellValue.new).toList());
        }
        final bytes = workbook.encode();
        if (bytes == null)
          throw StateError('Excel workbook could not be generated.');
        _saveBrowserFile(
          '$filename.xlsx',
          bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      } else {
        final csv = [
          headers,
          ...values,
        ].map((row) => row.map(_csvEscape).join(',')).join('\r\n');
        _saveBrowserFile(
          '$filename.csv',
          utf8.encode('\uFEFF$csv'),
          'text/csv;charset=utf-8',
        );
      }
      if (mounted) _notice('${rows.length} order(s) exported.');
    } catch (e) {
      if (mounted) _notice('Report export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _notice(String text, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: isError ? Colors.red.shade700 : _ink,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      drawer: wide ? null : Drawer(child: _navigation()),
      body: Row(
        children: [
          if (wide) SizedBox(width: 254, child: _navigation()),
          Expanded(
            child: Column(
              children: [
                _topBar(wide),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                      ? _errorPanel()
                      : _content(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigation() => Container(
    color: const Color(0xFF0B2545),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 23, 18, 21),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF123F73), Color(0xFF081D38)],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandLogo(width: 180, height: 65, onDark: true),
                SizedBox(height: 9),
                Text(
                  'ADMIN CONSOLE',
                  style: TextStyle(
                    color: Color(0xFFD8E8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
              itemCount: _sections.length,
              separatorBuilder: (context, index) => const SizedBox(height: 5),
              itemBuilder: (context, i) => _SidebarMenuItem(
                label: _sections[i].$1,
                icon: _sections[i].$2,
                selected: i == selected,
                onTap: () {
                  setState(() {
                    selected = i;
                    if (i != 2) productMode = 0;
                  });
                  if (MediaQuery.sizeOf(context).width < 1000) {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x334A6A8C))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF183D67),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin profile',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Administrator',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFFB9CADB),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF153A63),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      await widget.repo.logout();
                      widget.onLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Sign out',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _topBar(bool wide) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE8EDF4))),
    ),
    child: Row(
      children: [
        if (!wide)
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sections[selected].$1,
                style: const TextStyle(
                  fontSize: 20,
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'RO Wholesale Dealer App',
                style: TextStyle(fontSize: 12, color: Color(0xFF8190A2)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh data',
          onPressed: refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.admin_panel_settings_outlined, color: _blue),
        ),
      ],
    ),
  );

  Widget _content() {
    switch (selected) {
      case 1:
        return _dealerPage();
      case 2:
        return _productsPage();
      case 3:
        return _categoriesPage();
      case 4:
        return _stockPage();
      case 5:
        return _ordersPage();
      case 6:
        return _paymentsPage();
      case 7:
        return _invoicesPage();
      case 8:
        return _reportsPage();
      default:
        return _overview();
    }
  }

  Widget _page(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(26), child: child);
  Widget _heading(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
              ),
            ],
          ),
        ),
        if (action != null) action,
      ],
    ),
  );

  Widget _overview() => _page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Good day, Admin',
          'Here is what is happening across your store today.',
          action: OutlinedButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Refresh'),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth > 900
                ? 4
                : box.maxWidth > 570
                ? 2
                : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: cols == 1 ? 3.2 : 1.65,
              children: [
                _metric(
                  'Total revenue',
                  _money(stats['totalRevenue']),
                  Icons.currency_rupee,
                  const Color(0xFFEAF1FF),
                  _blue,
                ),
                _metric(
                  'Total orders',
                  '${stats['totalOrders'] ?? orders.length}',
                  Icons.shopping_bag_outlined,
                  const Color(0xFFEAF8F2),
                  const Color(0xFF179B65),
                ),
                _metric(
                  'Dealers',
                  '${stats['totalUsers'] ?? dealers.length}',
                  Icons.people_outline,
                  const Color(0xFFFFF5E7),
                  const Color(0xFFDE8B16),
                ),
                _metric(
                  'Products',
                  '${stats['totalProducts'] ?? products.length}',
                  Icons.inventory_2_outlined,
                  const Color(0xFFF2EDFF),
                  const Color(0xFF7953C7),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, box) => Flex(
            direction: box.maxWidth > 850 ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIfHorizontal(
                horizontal: box.maxWidth > 850,
                child: _chartCard(),
              ),
              SizedBox(
                width: box.maxWidth > 850 ? 18 : 0,
                height: box.maxWidth > 850 ? 0 : 18,
              ),
              ExpandedIfHorizontal(
                horizontal: box.maxWidth > 850,
                child: _quickStats(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ordersTable(orders.take(5).toList(), compact: true),
      ],
    ),
  );

  Widget _metric(
    String title,
    String value,
    IconData icon,
    Color bg,
    Color fg,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: fg, size: 19),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 25,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chartCard() {
    final chart = _map(analytics['chart']);
    final values = _numbers(chart['revenueData']);
    final labels = (chart['labels'] as List? ?? []).map((e) => '$e').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue overview',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Recent sales performance',
              style: TextStyle(color: Color(0xFF8190A2), fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 190,
              child: values.isEmpty
                  ? const Center(
                      child: Text(
                        'No revenue data yet',
                        style: TextStyle(color: Color(0xFF8190A2)),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < values.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _compactMoney(values[i]),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF718096),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Container(
                                    height:
                                        (values[i] <= 0
                                                ? 4
                                                : (values.reduce(
                                                            (a, b) =>
                                                                a > b ? a : b,
                                                          ) <=
                                                          0
                                                      ? 4
                                                      : values[i] /
                                                            values.reduce(
                                                              (a, b) =>
                                                                  a > b ? a : b,
                                                            ) *
                                                            125))
                                            .toDouble(),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF70A1FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    i < labels.length ? labels[i] : '',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF8190A2),
                                    ),
                                  ),
                                ],
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

  Widget _quickStats() {
    final pending = dealers
        .where((d) => '${d['status']}'.toLowerCase() == 'pending')
        .length;
    final low = products
        .where(
          (p) =>
              _int(p['stock_quantity'] ?? p['stock'], 50) <=
              _int(p['min_stock'] ?? p['minStock'], 10),
        )
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Needs attention',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 12),
            _attention(
              Icons.person_add_alt_1,
              '$pending dealers awaiting approval',
              () => setState(() => selected = 1),
            ),
            const Divider(height: 22),
            _attention(
              Icons.warning_amber_rounded,
              '$low products at low stock',
              () => setState(() => selected = 4),
            ),
            const Divider(height: 22),
            _attention(
              Icons.receipt_long_outlined,
              '${orders.where((o) => '${o['invoiceNumber'] ?? ''}'.isNotEmpty && o['invoiceNumber'] != null).length} invoices available',
              () => setState(() => selected = 7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attention(IconData icon, String text, VoidCallback tap) => InkWell(
    onTap: tap,
    child: Row(
      children: [
        Icon(icon, color: _blue, size: 19),
        const SizedBox(width: 11),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, color: _ink)),
        ),
        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8190A2)),
      ],
    ),
  );

  Widget _dealerPage() => _page(
    Column(
      children: [
        _heading(
          'Dealer approval',
          'Review registered dealers and update their approval status.',
        ),
        _tableCard(
          ['DEALER', 'CONTACT', 'BUSINESS', 'STATUS', 'JOINED', 'ACTIONS'],
          dealers
              .map(
                (d) => [
                  _primaryCell(d['name'] ?? '—', d['email'] ?? ''),
                  Text('${d['mobile'] ?? '—'}'),
                  Text('${d['business'] ?? '—'}'),
                  _status('${d['status'] ?? 'pending'}'),
                  Text(_date(d['createdAt'])),
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Approve',
                        onPressed: () => updateDealer(d, 'approved'),
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF168A5B),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reject',
                        onPressed: () => updateDealer(d, 'rejected'),
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: Color(0xFFD45252),
                        ),
                      ),
                    ],
                  ),
                ],
              )
              .toList(),
          empty: 'No dealers found.',
        ),
      ],
    ),
  );

  Widget _productsPage() => productMode == 1
      ? _bulkProductsPage()
      : _page(
          Column(
            children: [
              _heading(
                'Products',
                'Create individual products or import a validated product sheet.',
                action: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showSingleProductForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Single Product'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => productMode = 1),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Bulk Products'),
                    ),
                  ],
                ),
              ),
              _tableCard(
                [
                  'IMAGE',
                  'PRODUCT',
                  'SKU',
                  'CATEGORY',
                  'BRAND',
                  'PURCHASE',
                  'DEALER PRICE',
                  'ACTIONS',
                  'STOCK',
                ],
                products
                    .map(
                      (p) => [
                        _adminImageThumbnail(p['img'] ?? p['image']),
                        _primaryCell(p['name'] ?? '—', '${p['id'] ?? ''}'),
                        Text('${p['sku'] ?? '—'}'),
                        Text('${p['category'] ?? '—'}'),
                        Text('${p['brand'] ?? '—'}'),
                        Text(_money(p['purchase_price'] ?? p['purchasePrice'])),
                        Text(_money(p['price'])),
                        Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Edit product',
                              onPressed: () =>
                                  _showSingleProductForm(product: p),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: _blue,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete product',
                              onPressed: () => _deleteProduct(p),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFFD45252),
                              ),
                            ),
                          ],
                        ),
                        Text('${p['stock_quantity'] ?? p['stock'] ?? '—'}'),
                      ],
                    )
                    .toList(),
                empty: 'No products found.',
              ),
            ],
          ),
        );

  Widget _bulkProductsPage() => _page(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Bulk products',
          'Upload an XLSX or CSV sheet. Review every row before importing valid, unique SKUs.',
          action: OutlinedButton.icon(
            onPressed: () => setState(() => productMode = 0),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Products'),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.upload_file_outlined,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose product sheet',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Accepted formats: .xlsx and .csv',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8190A2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickBulkFile,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Browse files'),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Text(
                  'Columns: Image, Product Name, SKU Code, Category, Brand, Purchase Price, Dealer Price, MRP, MOQ, Stock, Product Description. Product Name, SKU Code and Dealer Price are required. Category values must match a category name, key or ID. Older Name, SKU and Description headers are also supported.',
                  style: TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _downloadBulkProductTemplate(asExcel: true),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Download Excel Template'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _downloadBulkProductTemplate(asExcel: false),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Download CSV Template'),
                    ),
                  ],
                ),
                if (importFilename != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          color: _blue,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            importFilename!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${importRows.length} rows',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (importError != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Card(
              color: const Color(0xFFFFF4F2),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFD45252),
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        importError!,
                        style: const TextStyle(
                          color: Color(0xFF9B3434),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (importRows.isNotEmpty) ...[
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final validCount = importRows
                  .where((r) => r.errors.isEmpty)
                  .length;
              final invalidCount = importRows.length - validCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _summaryChip(
                    '${importRows.length} total rows',
                    Icons.table_rows_outlined,
                    _ink,
                  ),
                  _summaryChip(
                    '$validCount ready to import',
                    Icons.check_circle_outline,
                    const Color(0xFF168A5B),
                  ),
                  _summaryChip(
                    '$invalidCount need attention',
                    Icons.warning_amber_outlined,
                    invalidCount == 0
                        ? const Color(0xFF8190A2)
                        : const Color(0xFFD45252),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import preview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 420,
                    child: ListView.separated(
                      itemCount: importRows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = importRows[index];
                        final product = row.product;
                        final ok = row.errors.isEmpty;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                ok
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: ok
                                    ? const Color(0xFF168A5B)
                                    : const Color(0xFFD45252),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 54,
                                child: Text(
                                  'Row ${row.rowNumber}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF8190A2),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Product Name: ${product['name'] ?? 'Unnamed product'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _ink,
                                      ),
                                    ),
                                    if ('${product['desc'] ?? ''}'
                                        .trim()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          'Product Description: ${product['desc']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF718096),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      'SKU ${product['sku'] ?? '—'}  ·  ${product['category'] ?? '—'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF8190A2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 110,
                                child: Text(
                                  _money(product['price']),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  ok ? 'Ready' : row.errors.join(' '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: ok
                                        ? const Color(0xFF168A5B)
                                        : const Color(0xFFD45252),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: importing
                            ? null
                            : () => setState(() {
                                importRows = [];
                                importError = null;
                                importFilename = null;
                              }),
                        child: const Text('Clear preview'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed:
                            importing ||
                                !importRows.any((r) => r.errors.isEmpty)
                            ? null
                            : _importBulkProducts,
                        icon: importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: Text(
                          importing
                              ? 'Importing…'
                              : 'Import ${importRows.where((r) => r.errors.isEmpty).length} valid products',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _summaryChip(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _categoriesPage() => _page(
    Column(
      children: [
        _heading(
          'Categories',
          'Add, edit or remove catalog categories.',
          action: FilledButton.icon(
            onPressed: () => _showCategoryForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add category'),
          ),
        ),
        _tableCard(
          [
            'IMAGE',
            'CATEGORY',
            'KEY',
            'DESCRIPTION',
            'DISPLAY ORDER',
            'ACTIONS',
          ],
          categories
              .map(
                (c) => [
                  _adminImageThumbnail(
                    c['image_url'] ?? c['image'] ?? c['img'],
                  ),
                  _primaryCell(
                    c['title'] ?? c['name'] ?? '—',
                    '${c['id'] ?? ''}',
                  ),
                  Text('${c['key_name'] ?? c['key'] ?? '—'}'),
                  Text(
                    '${c['description'] ?? '—'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('${c['display_order'] ?? '—'}'),
                  Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Edit category',
                        onPressed: () => _showCategoryForm(category: c),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 19,
                          color: _blue,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete category',
                        onPressed: () => _deleteCategory(c),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: Color(0xFFD45252),
                        ),
                      ),
                    ],
                  ),
                ],
              )
              .toList(),
          empty: 'No categories found.',
        ),
      ],
    ),
  );

  Widget _stockPage() {
    final low = products
        .where(
          (p) =>
              _int(p['stock_quantity'] ?? p['stock'], 50) <=
              _int(p['min_stock'] ?? p['minStock'], 10),
        )
        .toList();
    return _page(
      Column(
        children: [
          _heading(
            'Stock management',
            'Inventory levels and low-stock alerts from product records.',
          ),
          LayoutBuilder(
            builder: (context, b) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: b.maxWidth > 700 ? 3 : 1,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: b.maxWidth > 700 ? 2.6 : 4,
              children: [
                _metric(
                  'Tracked items',
                  '${products.length}',
                  Icons.inventory_2_outlined,
                  const Color(0xFFEAF1FF),
                  _blue,
                ),
                _metric(
                  'Low stock',
                  '${low.length}',
                  Icons.warning_amber_outlined,
                  const Color(0xFFFFF5E7),
                  const Color(0xFFDE8B16),
                ),
                _metric(
                  'Out of stock',
                  '${products.where((p) => _int(p['stock_quantity'] ?? p['stock'], 50) == 0).length}',
                  Icons.remove_shopping_cart_outlined,
                  const Color(0xFFFFEEEE),
                  const Color(0xFFD45252),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _tableCard(
            [
              'PRODUCT',
              'SKU',
              'CATEGORY',
              'AVAILABLE STOCK',
              'MINIMUM STOCK',
              'LEVEL',
            ],
            products.map((p) {
              final stock = _int(p['stock_quantity'] ?? p['stock'], 50);
              final min = _int(p['min_stock'] ?? p['minStock'], 10);
              return [
                _primaryCell(p['name'] ?? '—', '${p['id'] ?? ''}'),
                Text('${p['sku'] ?? '—'}'),
                Text('${p['category'] ?? '—'}'),
                Text('$stock'),
                Text('$min'),
                _status(
                  stock == 0
                      ? 'out of stock'
                      : stock <= min
                      ? 'low stock'
                      : 'in stock',
                ),
              ];
            }).toList(),
            empty: 'No stock records found.',
          ),
        ],
      ),
    );
  }

  Widget _ordersPage() => _page(
    Column(
      children: [
        _heading('Orders', 'Track orders and update their fulfillment status.'),
        _ordersTable(orders),
        const SizedBox(height: 24),
        _heading(
          'Shop delivery details',
          'Assign orders to an active shop employee and review confirmed item quantities, values and adjustments.',
        ),
        ...orders.map(_shopOrderDeliveryDetails),
      ],
    ),
  );

  Widget _shopOrderDeliveryDetails(Map<String, dynamic> order) {
    final orderId = '${order['orderId'] ?? order['id'] ?? ''}';
    final items = _rows(order['items']);
    final shopNames =
        shopEmployees
            .where((employee) => employee['active'] == true)
            .map(
              (employee) =>
                  '${employee['shopName'] ?? employee['shop_name'] ?? ''}'
                      .trim(),
            )
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final currentShop = '${order['shopName'] ?? ''}';
    if (currentShop.isNotEmpty && !shopNames.contains(currentShop)) {
      shopNames.insert(0, currentShop);
    }
    final assignmentValue = currentShop.isEmpty ? '' : currentShop;
    final orderedQuantity = items.fold<int>(
      0,
      (sum, item) =>
          sum + (_int(item['orderedQuantity'] ?? item['quantity'], 0)),
    );
    final deliveredQuantity = _int(order['deliveredQuantity'], 0);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: _status(
          '${order['deliveryStatus'] ?? order['status'] ?? 'Pending'}',
        ),
        title: Text(
          'Order #$orderId  ·  ${order['userBusiness'] ?? order['userName'] ?? 'Dealer'}',
        ),
        subtitle: Text(
          '${order['deliveryStatus'] ?? order['status'] ?? 'Pending'}  ·  '
          '$deliveredQuantity / $orderedQuantity units confirmed  ·  '
          'Original ${_money(order['originalOrderValue'])}  ·  '
          'Delivered ${_money(order['deliveredValue'])}  ·  '
          'Undelivered ${_int(order['undeliveredQuantity'], 0)}  ·  '
          'Adjustment ${_money(order['refundAmount'])}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  Text('Vendor: ${order['userName'] ?? 'Dealer'}'),
                  Text('Company: ${order['userBusiness'] ?? 'Not provided'}'),
                  Text(
                    'Order date: ${_date(order['orderDate'] ?? order['createdAt'])}',
                  ),
                  Text(
                    'Due date: ${order['dueDate'] == null ? 'Not provided' : _date(order['dueDate'])}',
                  ),
                  Text(
                    'Delivered: ${order['deliveredAt'] == null ? 'Not confirmed' : DateTime.tryParse('${order['deliveredAt']}')?.toLocal().toString().split('.').first ?? order['deliveredAt']}',
                  ),
                  Text(
                    'Confirmed by: ${order['deliveredBy'] ?? 'Not available'}',
                  ),
                ],
              ),
            ),
          ),
          if (shopNames.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: assignmentValue,
              decoration: const InputDecoration(
                labelText: 'Assign this order to a shop',
                prefixIcon: Icon(Icons.store_outlined),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not assigned')),
                ...shopNames.map(
                  (name) => DropdownMenuItem(value: name, child: Text(name)),
                ),
              ],
              onChanged: (value) {
                if (value != null && value != assignmentValue) {
                  assignOrderToShop(order, value);
                }
              },
            )
          else
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Create an active Shop Employee account before assigning orders.',
                  style: TextStyle(color: Color(0xFF71839D)),
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text('No order items were returned by the API.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Ordered Qty')),
                  DataColumn(label: Text('Actual Delivered Qty')),
                  DataColumn(label: Text('Dealer Price')),
                  DataColumn(label: Text('Delivered Value')),
                  DataColumn(label: Text('Undelivered Qty')),
                  DataColumn(label: Text('Refund / Adjustment')),
                  DataColumn(label: Text('Refund Status')),
                  DataColumn(label: Text('Delivery Status')),
                ],
                rows: items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text('${item['name'] ?? 'Product'}')),
                          DataCell(
                            Text(
                              '${item['orderedQuantity'] ?? item['quantity'] ?? 0}',
                            ),
                          ),
                          DataCell(
                            Text('${item['actualDeliveredQuantity'] ?? 0}'),
                          ),
                          DataCell(
                            Text(
                              _money(
                                item['dealerPrice'] ?? item['numericPrice'],
                              ),
                            ),
                          ),
                          DataCell(Text(_money(item['deliveredValue']))),
                          DataCell(Text('${item['undeliveredQuantity'] ?? 0}')),
                          DataCell(Text(_money(item['refundAmount']))),
                          DataCell(
                            Text('${item['refundStatus'] ?? 'not_required'}'),
                          ),
                          DataCell(
                            Text(
                              '${item['deliveryStatus'] ?? 'Pending'}',
                              style: TextStyle(
                                color: _deliveryColor(
                                  item['deliveryStatus'] ?? 'Pending',
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Status: ${order['deliveryStatus'] ?? order['status'] ?? 'Pending'}',
              style: TextStyle(
                color: _deliveryColor(
                  order['deliveryStatus'] ?? order['status'],
                ),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersTable(
    List<Map<String, dynamic>> list, {
    bool compact = false,
  }) => _tableCard(
    compact
        ? ['ORDER', 'DEALER', 'DATE', 'TOTAL', 'STATUS']
        : ['ORDER', 'DEALER', 'DATE', 'PAYMENT', 'TOTAL', 'STATUS', 'UPDATE'],
    list.map((o) {
      final cells = <Widget>[
        _primaryCell(
          '#${o['orderId'] ?? o['id'] ?? '—'}',
          '${(o['items'] as List? ?? []).length} line items',
        ),
        _primaryCell(o['userName'] ?? '—', '${o['userEmail'] ?? ''}'),
        Text(_date(o['createdAt'])),
        if (!compact) Text('${o['paymentMethod'] ?? '—'}'),
        Text(_money(o['grandTotal'] ?? o['total'])),
        _status('${o['status'] ?? 'Processing'}'),
      ];
      if (!compact) {
        cells.add(
          DropdownButton<String>(
            value: _orderStatuses.contains('${o['status'] ?? 'Processing'}')
                ? '${o['status'] ?? 'Processing'}'
                : 'Processing',
            underline: const SizedBox(),
            items: _orderStatuses
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: (s) {
              if (s != null) updateOrder(o, s);
            },
          ),
        );
      }
      return cells;
    }).toList(),
    empty: 'No orders found.',
  );

  Widget _paymentsPage() {
    final methods = <String, int>{};
    for (final o in orders) {
      final key = '${o['paymentMethod'] ?? 'Not specified'}';
      methods[key] = (methods[key] ?? 0) + 1;
    }
    return _page(
      Column(
        children: [
          _heading(
            'Payments',
            'Payment method and order totals recorded at checkout.',
          ),
          LayoutBuilder(
            builder: (context, b) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: b.maxWidth > 700 ? 3 : 1,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: b.maxWidth > 700 ? 2.5 : 4,
              children: methods.entries
                  .map(
                    (e) => _metric(
                      e.key,
                      '${e.value} orders',
                      Icons.account_balance_wallet_outlined,
                      const Color(0xFFEAF8F2),
                      const Color(0xFF179B65),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          _tableCard(
            ['ORDER', 'DEALER', 'METHOD', 'AMOUNT', 'PAYMENT STATUS', 'DATE'],
            orders
                .map(
                  (o) => [
                    _primaryCell(
                      '#${o['orderId'] ?? '—'}',
                      '${o['userEmail'] ?? ''}',
                    ),
                    Text('${o['userName'] ?? '—'}'),
                    Text('${o['paymentMethod'] ?? '—'}'),
                    Text(_money(o['grandTotal'])),
                    _status(o['paymentStatus']?.toString() ?? 'pending'),
                    Text(_date(o['createdAt'])),
                  ],
                )
                .toList(),
            empty: 'No payment records found.',
          ),
        ],
      ),
    );
  }

  Widget _invoicesPage() {
    final invoiced = orders
        .where(
          (o) =>
              o['invoiceNumber'] != null && '${o['invoiceNumber']}'.isNotEmpty,
        )
        .toList();
    return _page(
      Column(
        children: [
          _heading(
            'Invoices',
            'Invoices attached to existing orders. Only orders with an invoice number are listed.',
          ),
          _tableCard(
            ['INVOICE', 'ORDER', 'DEALER', 'GST', 'TOTAL', 'ISSUED'],
            invoiced
                .map(
                  (o) => [
                    _primaryCell(
                      '${o['invoiceNumber']}',
                      '${o['userEmail'] ?? ''}',
                    ),
                    Text('#${o['orderId'] ?? '—'}'),
                    Text('${o['userName'] ?? '—'}'),
                    Text(_money(o['gst'])),
                    Text(_money(o['grandTotal'])),
                    Text(_date(o['createdAt'])),
                  ],
                )
                .toList(),
            empty: 'No invoices are available yet.',
          ),
        ],
      ),
    );
  }

  Widget _reportsPage() {
    final revenue = _map(analytics['revenue']);
    final top = _rows(analytics['topProducts']);
    return _page(
      Column(
        children: [
          _heading(
            'Reports',
            'Filter orders by date and export detailed reports.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'daily', label: Text('Daily')),
                          ButtonSegment(
                            value: 'monthly',
                            label: Text('Monthly'),
                          ),
                          ButtonSegment(
                            value: 'custom',
                            label: Text('Custom range'),
                          ),
                        ],
                        selected: {reportPeriod},
                        onSelectionChanged: (values) =>
                            setState(() => reportPeriod = values.first),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickReportDate(range: reportPeriod == 'custom'),
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: Text(
                          reportPeriod == 'custom'
                              ? (reportRange == null
                                    ? 'Choose dates'
                                    : '${_date(reportRange!.start.toIso8601String())} – ${_date(reportRange!.end.toIso8601String())}')
                              : reportPeriod == 'monthly'
                              ? _monthLabel(reportDate)
                              : _date(reportDate.toIso8601String()),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: exporting
                            ? null
                            : () =>
                                  _downloadReport(reportPeriod, asExcel: false),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Download CSV'),
                      ),
                      FilledButton.icon(
                        onPressed: exporting
                            ? null
                            : () =>
                                  _downloadReport(reportPeriod, asExcel: true),
                        icon: const Icon(Icons.table_view_outlined, size: 18),
                        label: const Text('Download Excel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_filteredReportOrders(reportPeriod).length} order(s) in this ${reportPeriod == 'custom'
                        ? 'date range'
                        : reportPeriod == 'monthly'
                        ? 'month'
                        : 'day'}',
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ordersTable(_filteredReportOrders(reportPeriod), compact: true),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, b) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: b.maxWidth > 800
                  ? 4
                  : b.maxWidth > 550
                  ? 2
                  : 1,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: b.maxWidth > 550 ? 1.7 : 3,
              children: [
                _metric(
                  'Today',
                  _money(revenue['todayRevenue']),
                  Icons.today_outlined,
                  const Color(0xFFEAF1FF),
                  _blue,
                ),
                _metric(
                  'This month',
                  _money(revenue['monthRevenue']),
                  Icons.calendar_month_outlined,
                  const Color(0xFFEAF8F2),
                  const Color(0xFF179B65),
                ),
                _metric(
                  'Average order',
                  _money(revenue['avgOrderValue']),
                  Icons.trending_up,
                  const Color(0xFFF2EDFF),
                  const Color(0xFF7953C7),
                ),
                _metric(
                  'Orders',
                  '${revenue['totalOrders'] ?? orders.length}',
                  Icons.shopping_bag_outlined,
                  const Color(0xFFFFF5E7),
                  const Color(0xFFDE8B16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _chartCard(),
          const SizedBox(height: 20),
          _tableCard(
            ['TOP PRODUCT', 'CATEGORY', 'UNITS SOLD', 'REVENUE'],
            top
                .map(
                  (p) => [
                    _primaryCell(p['name'] ?? '—', '${p['id'] ?? ''}'),
                    Text('${p['category'] ?? '—'}'),
                    Text('${p['unitsSold'] ?? 0}'),
                    Text(_money(p['totalRevenue'])),
                  ],
                )
                .toList(),
            empty: 'Sales reports will appear after orders are placed.',
          ),
        ],
      ),
    );
  }

  Widget _tableCard(
    List<String> headers,
    List<List<Widget>> rows, {
    String empty = 'No records.',
  }) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                empty,
                style: const TextStyle(color: Color(0xFF8190A2)),
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 28,
              horizontalMargin: 20,
              headingRowHeight: 48,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 76,
              columns: headers
                  .map(
                    (h) => DataColumn(
                      label: Text(
                        h,
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: .7,
                          color: Color(0xFF8190A2),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              rows: rows
                  .map(
                    (cells) =>
                        DataRow(cells: cells.map((c) => DataCell(c)).toList()),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );

  Widget _adminImageThumbnail(dynamic raw) {
    final image = _adminImageUrl(raw);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: const Color(0xFFF1F4F8),
        child: image.isEmpty
            ? const Icon(Icons.image_outlined, color: Color(0xFF9AA7B5))
            : Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFF9AA7B5),
                ),
              ),
      ),
    );
  }

  Widget _primaryCell(dynamic title, String subtitle) => SizedBox(
    width: 145,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8190A2), fontSize: 10),
          ),
      ],
    ),
  );
  Widget _status(String value) {
    final v = value.toLowerCase();
    final color = v == 'delivered' || v.contains('approv') || v == 'in stock'
        ? const Color(0xFF168A5B)
        : v.contains('partial')
        ? const Color(0xFFB7791F)
        : v.contains('pending') ||
              v.contains('not delivered') ||
              v.contains('reject') ||
              v.contains('cancel') ||
              v.contains('out of stock')
        ? const Color(0xFFD45252)
        : const Color(0xFFB7791F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _errorPanel() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: Color(0xFFD45252),
            size: 42,
          ),
          const SizedBox(height: 12),
          const Text(
            'Could not load admin data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF718096)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

const _orderStatuses = [
  'Processing',
  'Confirmed',
  'Shipped',
  'Delivered',
  'Cancelled',
];

String _adminImageUrl(dynamic raw) {
  final value = '$raw'.trim();
  if (value.isEmpty || value.startsWith('data:')) return value;
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.hasScheme || value.startsWith('//'))) return value;
  final api = Uri.tryParse(ApiClient.defaultBaseUrl);
  if (api == null) return value;
  final origin = api.replace(path: '/', query: null, fragment: null);
  return origin
      .resolve(value.startsWith('/') ? value.substring(1) : value)
      .toString();
}

class _AdminImagePicker extends StatefulWidget {
  const _AdminImagePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  State<_AdminImagePicker> createState() => _AdminImagePickerState();
}

class _AdminImagePickerState extends State<_AdminImagePicker> {
  bool picking = false;
  String? error;

  Future<void> _pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('Could not read image.');
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Image must be 5 MB or smaller.');
      }
      final extension = file.extension?.toLowerCase();
      final mime = switch (extension) {
        'jpg' || 'jpeg' => 'jpeg',
        'png' => 'png',
        'webp' => 'webp',
        _ => throw const FormatException('Choose a JPG, PNG, or WebP image.'),
      };
      widget.onChanged('data:image/$mime;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (mounted)
        setState(
          () => error = e.toString().replaceFirst('FormatException: ', ''),
        );
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Product/category image',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 64,
              height: 64,
              color: const Color(0xFFF1F4F8),
              child: widget.value.isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFF9AA7B5))
                  : widget.value.startsWith('data:image/')
                  ? Image.memory(
                      base64Decode(
                        widget.value.substring(widget.value.indexOf(',') + 1),
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_outlined),
                    )
                  : Image.network(
                      _adminImageUrl(widget.value),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: picking ? null : _pick,
            icon: picking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(picking ? 'Reading…' : 'Upload image'),
          ),
          if (widget.value.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove image',
              onPressed: picking ? null : () => widget.onChanged(''),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      if (error != null) ...[
        const SizedBox(height: 4),
        Text(
          error!,
          style: const TextStyle(color: Color(0xFFD45252), fontSize: 12),
        ),
      ],
    ],
  );
}

class _SidebarMenuItem extends StatefulWidget {
  const _SidebarMenuItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarMenuItem> createState() => _SidebarMenuItemState();
}

class _SidebarMenuItemState extends State<_SidebarMenuItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF1B4D80)
                  : hovered
                  ? const Color(0xFF14385F)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: active ? 23 : 0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF64B5F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(width: active ? 9 : 12),
                Icon(
                  widget.icon,
                  size: 19,
                  color: active ? Colors.white : const Color(0xFFB3C4D7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFFD1DCE8),
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportProduct {
  const _ImportProduct(this.rowNumber, this.product, this.errors);
  final int rowNumber;
  final Map<String, dynamic> product;
  final List<String> errors;
}

class _ImportParseResult {
  const _ImportParseResult(this.rows, this.error);
  final List<_ImportProduct> rows;
  final String? error;
}

String _categoryKey(Map<String, dynamic> category) =>
    '${category['key_name'] ?? category['key'] ?? category['title'] ?? category['name'] ?? ''}'
        .trim();

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

double? _number(String value) {
  final cleaned = value
      .trim()
      .replaceAll(',', '')
      .replaceAll(RegExp(r'^(₹|Rs\.?\s*)', caseSensitive: false), '');
  return double.tryParse(cleaned);
}

String _headerKey(String value) => value
    .replaceAll('\uFEFF', '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

String _cellText(CellValue? value) {
  if (value == null) return '';
  if (value is TextCellValue) return value.value.text ?? '';
  if (value is IntCellValue) return '${value.value}';
  if (value is DoubleCellValue) return '${value.value}';
  if (value is BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
  if (value is DateCellValue)
    return value.asDateTimeLocal().toIso8601String().split('T').first;
  if (value is DateTimeCellValue)
    return value.asDateTimeLocal().toIso8601String();
  if (value is FormulaCellValue) return value.formula;
  return value.toString();
}

List<List<String>> _parseWorkbook(List<int> bytes) {
  final workbook = Excel.decodeBytes(bytes);
  for (final sheetName in workbook.tables.keys) {
    final rows = workbook.tables[sheetName]!.rows
        .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
        .toList();
    if (rows.any((row) => row.any((cell) => cell.trim().isNotEmpty)))
      return rows;
  }
  return [];
}

List<List<String>> _parseCsv(String source) {
  final text = source.replaceFirst('\uFEFF', '');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      row.add(cell.toString());
      cell.clear();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(char);
    }
  }
  if (quoted)
    throw const FormatException('CSV has an unterminated quoted field.');
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

void _saveBrowserFile(String name, List<int> bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = name
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

String _dateFilePart(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _monthLabel(DateTime value) =>
    '${_monthNames[value.month - 1]} ${value.year}';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class ExpandedIfHorizontal extends StatelessWidget {
  const ExpandedIfHorizontal({
    required this.horizontal,
    required this.child,
    super.key,
  });
  final bool horizontal;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      horizontal ? Expanded(child: child) : child;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _rows(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];
List<double> _numbers(dynamic v) => v is List
    ? v.map((e) => (num.tryParse('$e') ?? 0).toDouble()).toList()
    : <double>[];
int _int(dynamic v, int fallback) => int.tryParse('$v') ?? fallback;
Color _deliveryColor(dynamic status) {
  final value = '$status'.toLowerCase();
  if (value == 'delivered') return const Color(0xFF168A5B);
  if (value.contains('partial')) return const Color(0xFFB7791F);
  return const Color(0xFFD45252);
}

String _money(dynamic v) {
  final n = num.tryParse('$v');
  return n == null ? '—' : '₹${n.toStringAsFixed(2)}';
}

String _compactMoney(double value) => value >= 100000
    ? '₹${(value / 100000).toStringAsFixed(1)}L'
    : value >= 1000
    ? '₹${(value / 1000).toStringAsFixed(1)}k'
    : '₹${value.toStringAsFixed(0)}';
String _date(dynamic value) {
  final d = DateTime.tryParse('$value');
  if (d == null) return '—';
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day/$month/${d.year}';
}
