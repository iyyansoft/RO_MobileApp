import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_auth_adapter.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

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
    final client = ApiClient();
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
        'availableCredit': invoiceData['availableCredit'] ?? 0,
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
      'availableCredit': responses[2].data?['availableCredit'] ?? 0,
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
        final response = await ApiClient().post<Map<String, dynamic>>(
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
            final response = await ApiClient().post<Map<String, dynamic>>(
              path,
              data: body,
            );
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
      final response = await ApiClient().post<Map<String, dynamic>>(
        path,
        data: body,
      );
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
      appBar: AppBar(
        title: const Text('My profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: () => _edit(user),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_refresh);
          await _accountData;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      child: Icon(Icons.storefront, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (user.gstNumber.isNotEmpty)
                      Text('GST: ${user.gstNumber}'),
                    Text(user.email),
                    Text(user.phoneNumber),
                    const SizedBox(height: 8),
                    Chip(label: Text(user.status.toUpperCase())),
                  ],
                ),
              ),
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: _accountData,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return ListTile(
                    title: const Text('Account details unavailable'),
                    subtitle: Text('${snapshot.error}'),
                    trailing: const Icon(Icons.refresh),
                    onTap: () => setState(_refresh),
                  );
                }
                final data = snapshot.data ?? {};
                final addresses = (data['addresses'] as List? ?? [])
                    .whereType<Map>()
                    .toList();
                final rewardHistory = (data['rewardHistory'] as List? ?? [])
                    .whereType<Map>()
                    .toList();
                final invoices = (data['invoices'] as List? ?? [])
                    .whereType<Map>()
                    .toList();
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: const Text('Reward points'),
                      trailing: Text('${data['rewards'] ?? 0}'),
                    ),
                    for (final entry in rewardHistory.take(3))
                      ListTile(
                        dense: true,
                        title: Text(
                          '${entry['description'] ?? entry['reason'] ?? 'Reward activity'}',
                        ),
                        trailing: Text('+${entry['pointsEarned'] ?? 0}'),
                      ),
                    ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Available credit'),
                      trailing: Text('₹${data['availableCredit'] ?? 0}'),
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Delivery addresses'),
                      trailing: TextButton.icon(
                        onPressed: () => _addressForm(user),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ),
                    if (addresses.isEmpty)
                      const ListTile(title: Text('No saved addresses')),
                    for (final address in addresses)
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(
                          '${address['label'] ?? address['addressType'] ?? 'Address'}${address['isDefault'] == true ? ' • Default' : ''}',
                        ),
                        subtitle: Text(
                          '${address['street'] ?? ''}, ${address['city'] ?? ''}, ${address['state'] ?? ''} ${address['pincode'] ?? ''}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Address actions',
                          onSelected: (action) =>
                              _addressAction(user, address, action),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            if (address['isDefault'] != true)
                              const PopupMenuItem(
                                value: 'default',
                                child: Text('Set default'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    const Divider(),
                    ListTile(
                      title: const Text('GST invoices'),
                      trailing: Text('${invoices.length}'),
                    ),
                    for (final invoice in invoices)
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(
                          '${invoice['invoiceNumber'] ?? invoice['orderId'] ?? 'Invoice'}',
                        ),
                        subtitle: Text('${invoice['date'] ?? ''}'),
                        trailing: Text('₹${invoice['amount'] ?? 0}'),
                      ),
                  ],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('My orders'),
              onTap: () => context.go('/orders'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              onTap: () => _changePassword(user),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Contact support'),
              onTap: () => _supportTicket(user),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
