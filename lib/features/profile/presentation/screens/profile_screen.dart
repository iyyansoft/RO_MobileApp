import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_auth_adapter.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../products/presentation/providers/wishlist_provider.dart';
import '../widgets/profile_sections.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<Map<String, dynamic>> _accountData;
  String? _loadedIdentity;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final user = ref.read(authProvider).currentUser;
    _loadedIdentity = '${user?.id}|${user?.email}';
    _accountData = _loadData(user);
  }

  Future<Map<String, dynamic>> _loadData(UserModel? user) async {
    final email = user?.email ?? '';
    if (email.isEmpty) return {};
    final client = ref.read(apiClientProvider);
    if (SupabaseConfig.dealerDataSessionActive && user != null) {
      final results = await Future.wait<dynamic>([
        const SupabaseDealerDataRepository().loadDealerProfile(user.id),
        const SupabaseDealerDataRepository().loadAddresses(user.id),
        const SupabaseDealerDataRepository().loadRewards(user.id),
        const SupabaseDealerDataRepository().loadGstInvoices(user.id, email),
      ]);
      if (mounted) {
        final profile = Map<String, dynamic>.from(results[0] as Map);
        ref
            .read(authProvider.notifier)
            .updateUser(
              user.copyWith(
                name: '${profile['name'] ?? user.name}',
                phoneNumber: '${profile['mobile'] ?? user.phoneNumber}',
                companyName: '${profile['business'] ?? user.companyName}',
                address: '${profile['address'] ?? user.address}',
                gstNumber: '${profile['gstNumber'] ?? user.gstNumber}',
              ),
            );
      }
      final rewards = results[2] as Map<String, dynamic>;
      final invoiceData = results[3] as Map<String, dynamic>;
      return {
        'addresses': results[1],
        'rewards': rewards['totalPoints'] ?? 0,
        'rewardHistory': rewards['history'] ?? [],
        'rewardsEarned': rewards['totalPointsEarned'],
        'creditLimit': invoiceData['creditLimit'],
        'availableCredit': invoiceData['availableCredit'],
        'outstandingAmount': invoiceData['outstandingAmount'],
        'invoices': invoiceData['invoices'] ?? [],
      };
    }
    final responses = await Future.wait([
      client.get<Map<String, dynamic>>(
        'user/addresses',
        queryParameters: {'email': email},
      ),
      client.get<Map<String, dynamic>>(
        'user/rewards',
        queryParameters: {'email': email},
      ),
      client.get<Map<String, dynamic>>(
        'user/gst-invoices',
        queryParameters: {'email': email},
      ),
    ]);
    return {
      'addresses': responses[0].data?['addresses'] ?? [],
      'rewards': responses[1].data?['totalPoints'] ?? 0,
      'rewardHistory': responses[1].data?['history'] ?? [],
      'rewardsEarned': responses[1].data?['totalPointsEarned'],
      'creditLimit': responses[2].data?['creditLimit'],
      'availableCredit': responses[2].data?['availableCredit'],
      'outstandingAmount': responses[2].data?['outstandingAmount'],
      'invoices': responses[2].data?['invoices'] ?? [],
    };
  }

  Future<void> _edit(UserModel user) async {
    final name = TextEditingController(text: user.name);
    final mobile = TextEditingController(text: user.phoneNumber);
    final business = TextEditingController(text: user.companyName);
    final address = TextEditingController(text: user.address);
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: mobile,
                  decoration: const InputDecoration(labelText: 'Mobile'),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      RegExp(r'^\d{10}$')
                          .hasMatch((v ?? '').replaceAll(RegExp(r'\D'), ''))
                      ? null
                      : 'Enter 10 digits',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: business,
                  decoration: const InputDecoration(labelText: 'Business'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
              ],
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
              if (form.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'mobile': mobile.text.replaceAll(RegExp(r'\D'), ''),
                  'business': business.text.trim(),
                  'address': address.text.trim(),
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    mobile.dispose();
    business.dispose();
    address.dispose();
    if (result == null) return;
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        await const SupabaseDealerDataRepository().updateDealerProfile(
          user.id,
          result,
        );
      } else {
        final response = await ref
            .read(apiClientProvider)
            .post<Map<String, dynamic>>(
              'user/update-profile',
              data: {'email': user.email, ...result},
            );
        final data = response.data ?? {};
        if (data['success'] != true) {
          throw ApiException(message: '${data['error'] ?? 'Update failed'}');
        }
      }
      ref
          .read(authProvider.notifier)
          .updateUser(
            user.copyWith(
              name: result['name'],
              phoneNumber: result['mobile'],
              companyName: result['business'],
              address: result['address'],
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        final user = ref.read(authProvider).currentUser;
        if (user == null) throw StateError('Sign in to update account data.');
        const repository = SupabaseDealerDataRepository();
        switch (path) {
          case 'user/addresses/save':
            await repository.saveAddress(user.id, body);
          case 'user/addresses/set-default':
            await repository.setDefaultAddress(
              user.id,
              '${body['addressId'] ?? ''}',
            );
          case 'user/addresses/delete':
            await repository.deleteAddress(
              user.id,
              '${body['addressId'] ?? ''}',
            );
          case 'user/support-ticket':
            await repository.createSupportTicket(user.id, user.email, body);
          default:
            // Password and other privileged/account operations stay on Express.
            final response = await ref
                .read(apiClientProvider)
                .post<Map<String, dynamic>>(path, data: body);
            final data = response.data ?? {};
            if (data['success'] != true) {
              throw ApiException(
                message: '${data['error'] ?? 'Request failed.'}',
              );
            }
        }
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_successMessage(path))));
        }
        return true;
      }
      final response = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(path, data: body);
      final data = response.data ?? {};
      if (data['success'] != true) {
        throw ApiException(message: '${data['error'] ?? 'Request failed.'}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${data['message'] ?? 'Saved successfully'}')),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return false;
    }
  }

  String _successMessage(String path) => switch (path) {
    'user/addresses/save' => 'Address saved successfully.',
    'user/addresses/set-default' => 'Default address updated.',
    'user/addresses/delete' => 'Address deleted.',
    'user/support-ticket' => 'Support request submitted.',
    _ => 'Saved successfully.',
  };

  Future<void> _addressForm(UserModel user, [Map? existing]) async {
    const fields = [
      'fullName',
      'phone',
      'businessName',
      'doorNo',
      'street',
      'area',
      'city',
      'district',
      'state',
      'pincode',
      'landmark',
      'gstNumber',
    ];
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field: TextEditingController(
          text:
              '${existing?[field] ?? (field == 'fullName'
                      ? user.name
                      : field == 'phone'
                      ? user.phoneNumber
                      : field == 'businessName'
                      ? user.companyName
                      : '')}',
        ),
    };
    final form = GlobalKey<FormState>();
    var addressType = '${existing?['addressType'] ?? 'Office'}';
    if (!const ['Office', 'Home', 'Warehouse', 'Other'].contains(addressType)) {
      addressType = 'Other';
    }
    var isDefault = existing?['isDefault'] == true;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add address' : 'Edit address'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in fields) ...[
                      TextFormField(
                        controller: controllers[field],
                        keyboardType: field == 'phone' || field == 'pincode'
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: {
                            'fullName': 'Full name',
                            'phone': '10 digit mobile',
                            'businessName': 'Business name',
                            'doorNo': 'Door number',
                            'street': 'Street',
                            'area': 'Area',
                            'city': 'City',
                            'district': 'District',
                            'state': 'State',
                            'pincode': '6 digit PIN code',
                            'landmark': 'Landmark',
                            'gstNumber': 'GST number',
                          }[field],
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if ([
                                'fullName',
                                'street',
                                'city',
                                'state',
                              ].contains(field) &&
                              text.isEmpty) {
                            return 'Required';
                          }
                          if (field == 'phone' &&
                              !RegExp(r'^\d{10}$').hasMatch(text)) {
                            return 'Enter 10 digits';
                          }
                          if (field == 'pincode' &&
                              !RegExp(r'^\d{6}$').hasMatch(text)) {
                            return 'Enter 6 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: addressType,
                      decoration: const InputDecoration(
                        labelText: 'Address type',
                      ),
                      items: const ['Office', 'Home', 'Warehouse', 'Other']
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => addressType = value ?? 'Office'),
                    ),
                    CheckboxListTile(
                      value: isDefault,
                      title: const Text('Set as default'),
                      onChanged: (value) =>
                          setDialogState(() => isDefault = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'email': user.email,
                  if (existing != null) 'id': existing['id'],
                  for (final field in fields)
                    field: controllers[field]!.text.trim(),
                  'addressType': addressType,
                  'isDefault': isDefault,
                });
              },
              child: const Text('Save address'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result == null) return;
    if (await _post('user/addresses/save', result) && mounted) {
      setState(_refresh);
    }
  }

  Future<void> _addressAction(
    UserModel user,
    Map address,
    String action,
  ) async {
    if (action == 'edit') return _addressForm(user, address);
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete address?'),
          content: const Text('This saved address will be removed.'),
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
      if (confirmed != true) return;
    }
    final path = action == 'default'
        ? 'user/addresses/set-default'
        : 'user/addresses/delete';
    if (await _post(path, {'email': user.email, 'addressId': address['id']}) &&
        mounted) {
      setState(_refresh);
    }
  }

  Future<void> _changePassword(UserModel user) async {
    final current = TextEditingController(),
        next = TextEditingController(),
        confirm = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                  validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) =>
                      (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (v) =>
                      v != next.text ? 'Passwords do not match' : null,
                ),
              ],
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
              if (form.currentState!.validate()) {
                Navigator.pop(context, {
                  'email': user.email,
                  'currentPassword': current.text,
                  'newPassword': next.text,
                });
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (result == null) return;
    if (SupabaseConfig.authEnabled &&
        SupabaseConfig.client.auth.currentSession != null) {
      try {
        await const SupabaseAuthAdapter().changePassword(
          expectedEmail: user.email,
          currentPassword: result['currentPassword'] ?? '',
          newPassword: result['newPassword'] ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
      return;
    }
    await _post('user/change-password', result);
  }

  Future<void> _supportTicket(UserModel user) async {
    final subject = TextEditingController(), message = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact support'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: message,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Describe your issue',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a message' : null,
                ),
              ],
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
              if (form.currentState!.validate()) {
                Navigator.pop(context, {
                  'email': user.email,
                  'name': user.name,
                  'subject': subject.text.trim().isEmpty
                      ? 'Dealer inquiry'
                      : subject.text.trim(),
                  'message': message.text.trim(),
                });
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    subject.dispose();
    message.dispose();
    if (result != null) await _post('user/support-ticket', result);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    if (_loadedIdentity != '${user?.id}|${user?.email}') {
      _refresh();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My profile')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sign in to view your dealer account.'),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A1118)
          : const Color(0xFFF3F7FC),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(_refresh);
            await _accountData;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final pad = width < 600 ? 16.0 : 32.0;
              final content = (width - pad * 2).clamp(0.0, 1180.0);
              final twoColumns = content >= 860;
              return ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: (width - content) / 2,
                  vertical: width < 600 ? 16 : 28,
                ),
                children: [
                  _pageHeader(isDark),
                  SizedBox(height: width < 600 ? 14 : 20),
                  ProfileSummaryCard(
                    user: user,
                    isDark: isDark,
                    onEdit: () => _edit(user),
                  ),
                  const SizedBox(height: _gap),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _accountData,
                    builder: (context, snapshot) => _accountSections(
                      user,
                      snapshot,
                      twoColumns: twoColumns,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: 90),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static const _gap = 20.0;

  Widget _pageHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Profile',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Manage your dealer account, rewards, credit and addresses',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  /// Rewards, credit, account details, addresses, invoices and options:
  /// two balanced columns on wide screens, one stacked column otherwise.
  Widget _accountSections(
    UserModel user,
    AsyncSnapshot<Map<String, dynamic>> snapshot, {
    required bool twoColumns,
    required bool isDark,
  }) {
    final options = _optionsCard(user, isDark);
    final account = ProfileSectionCard(
      title: 'Business Information',
      icon: Icons.storefront_rounded,
      isDark: isDark,
      child: InfoRows(
        isDark: isDark,
        rows: [
          if (user.companyName.trim().isNotEmpty)
            (Icons.business_rounded, 'Business', user.companyName.trim()),
          if (user.gstNumber.trim().isNotEmpty)
            (Icons.receipt_rounded, 'GST number', user.gstNumber.trim()),
          if (user.address.trim().isNotEmpty)
            (
              Icons.home_work_outlined,
              'Registered address',
              user.address.trim(),
            ),
        ],
      ),
    );

    List<Widget> dataCards;
    List<Widget> dataCardsRight;
    if (snapshot.connectionState != ConnectionState.done) {
      dataCards = [_loadingCard(isDark)];
      dataCardsRight = [_loadingCard(isDark)];
    } else if (snapshot.hasError) {
      final error = _errorCard(snapshot.error, isDark);
      dataCards = [error];
      dataCardsRight = [];
    } else {
      final data = snapshot.data ?? {};
      List<Map> list(String key) =>
          (data[key] as List? ?? []).whereType<Map>().toList();
      final addresses = list('addresses');
      final rewards = RewardsCard(
        totalPoints: (num.tryParse('${data['rewards'] ?? 0}') ?? 0).toInt(),
        totalEarned: num.tryParse('${data['rewardsEarned'] ?? ''}')?.toInt(),
        history: list('rewardHistory'),
        isDark: isDark,
      );
      final credit = CreditCard(
        availableCredit: num.tryParse('${data['availableCredit'] ?? ''}')
            ?.toDouble(),
        creditLimit: num.tryParse('${data['creditLimit'] ?? ''}')?.toDouble(),
        outstanding: num.tryParse('${data['outstandingAmount'] ?? ''}')
            ?.toDouble(),
        isDark: isDark,
      );
      final addressCard = ProfileSectionCard(
        title: 'Delivery Addresses',
        icon: Icons.local_shipping_rounded,
        iconColor: const Color(0xFF059669),
        isDark: isDark,
        trailing: TextButton.icon(
          key: const ValueKey('address-add'),
          onPressed: () => _addressForm(user),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add'),
        ),
        child: addresses.isEmpty
            ? const Text(
                'No saved addresses yet.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
              )
            : Column(
                children: [
                  for (var i = 0; i < addresses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    AddressTile(
                      address: addresses[i],
                      isDark: isDark,
                      onAction: (action) =>
                          _addressAction(user, addresses[i], action),
                    ),
                  ],
                ],
              ),
      );
      final invoices = list('invoices');
      final invoiceCard = ProfileSectionCard(
        title: 'GST Invoices',
        icon: Icons.receipt_long_rounded,
        iconColor: const Color(0xFF7C3AED),
        isDark: isDark,
        trailing: Text(
          '${invoices.length}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF7C3AED),
          ),
        ),
        child: InvoiceList(invoices: invoices, isDark: isDark),
      );
      dataCards = [rewards, addressCard, invoiceCard];
      dataCardsRight = [credit];
    }

    Widget column(List<Widget> cards) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          cards[i],
        ],
      ],
    );

    if (twoColumns) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: column(dataCards)),
          const SizedBox(width: _gap),
          Expanded(
            flex: 5,
            child: column([...dataCardsRight, account, options]),
          ),
        ],
      );
    }
    // Phones / tablets: rewards and credit first, then the rest.
    return column([
      if (dataCards.isNotEmpty) dataCards.first,
      ...dataCardsRight,
      account,
      ...dataCards.skip(1),
      options,
    ]);
  }

  Widget _optionsCard(UserModel user, bool isDark) {
    return ProfileSectionCard(
      title: 'Account & Settings',
      icon: Icons.settings_rounded,
      iconColor: const Color(0xFF475569),
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileOptionTile(
            icon: Icons.shopping_bag_outlined,
            label: 'My orders',
            subtitle: 'Track orders and delivery status',
            isDark: isDark,
            onTap: () => context.go('/orders'),
          ),
          ProfileOptionTile(
            icon: Icons.favorite_outline_rounded,
            label: 'My wishlist',
            subtitle: 'Products you saved',
            trailingText: '${ref.watch(wishlistProvider).length}',
            color: const Color(0xFFE11D48),
            isDark: isDark,
            onTap: () => context.push('/wishlist'),
          ),
          ProfileOptionTile(
            icon: Icons.lock_outline_rounded,
            label: 'Change password',
            subtitle: 'Update your sign-in password',
            color: const Color(0xFF7C3AED),
            isDark: isDark,
            onTap: () => _changePassword(user),
          ),
          ProfileOptionTile(
            icon: Icons.support_agent_rounded,
            label: 'Contact support',
            subtitle: 'Raise a ticket with our team',
            color: const Color(0xFF0E7490),
            isDark: isDark,
            onTap: () => _supportTicket(user),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('profile-sign-out'),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFECACA)),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingCard(bool isDark) => Container(
    height: 180,
    decoration: profileCardDecoration(isDark),
    alignment: Alignment.center,
    child: const CircularProgressIndicator(),
  );

  Widget _errorCard(Object? error, bool isDark) => ProfileSectionCard(
    title: 'Account details unavailable',
    icon: Icons.cloud_off_rounded,
    iconColor: const Color(0xFFDC2626),
    isDark: isDark,
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$error',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(_refresh),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}
