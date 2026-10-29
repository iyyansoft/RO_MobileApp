import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/cart/domain/models/cart_item_model.dart';
import '../../features/products/domain/models/product_model.dart';
import 'supabase_config.dart';

/// Direct Supabase access for dealer-owned, low-risk data only. RLS remains
/// authoritative; the dealer ID is included solely to narrow queries.
/// Checkout, payment, invoice, admin and shop writes stay on Express.
class SupabaseDealerDataRepository {
  const SupabaseDealerDataRepository();

  static const _secureStorage = FlutterSecureStorage();
  static const _pendingCartAddPrefix = 'supabase_cart_add_request_v1';
  static const _addressColumns =
      'id,user_id,label,business_name,street,city,state,pincode,phone,is_default,full_name,door_no,area,district,landmark,address_type,gst_number,created_at';

  Future<List<CartItemModel>> loadCart(
    String userId, {
    List<ProductModel> cachedProducts = const [],
  }) async {
    _requireUser(userId);
    final rows = await SupabaseConfig.client
        .from('cart_items')
        .select('product_id,quantity')
        .eq('user_id', userId);
    if (rows.isEmpty) return const [];

    final ids = rows
        .map((row) => '${row['product_id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];
    final productRows = await SupabaseConfig.client
        .from('catalog_products')
        .select(
          'id,category_id,category_key,category_name,sku,name,brand,price,'
          'dealer_price,mrp,moq,badge,rating,img,description,desc,specs,'
          'features,applications,stock_quantity,status,created_at',
        )
        .inFilter('id', ids);
    return cartRowsToModels(rows, productRows, cachedProducts);
  }

  Future<void> addCartItem(
    String userId,
    String productId,
    int quantity,
  ) async {
    _requireUser(userId);
    if (quantity < 1) throw StateError('Quantity must be at least 1.');
    // Keep the same key after an ambiguous network failure, including app
    // restarts, so retrying a committed add cannot increment the cart twice.
    final storageKey = _pendingCartAddKey(userId, productId, quantity);
    final requestId =
        await _secureStorage.read(key: storageKey) ?? _newRequestId();
    await _secureStorage.write(key: storageKey, value: requestId);
    await SupabaseConfig.client.rpc(
      'ro_add_cart_item',
      params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_request_id': requestId,
      },
    );
    await _secureStorage.delete(key: storageKey);
  }

  Future<void> updateCartQuantity(
    String userId,
    String productId,
    int quantity,
  ) async {
    _requireUser(userId);
    if (quantity < 1) throw StateError('Quantity must be at least 1.');
    await SupabaseConfig.client.rpc(
      'ro_update_cart_item',
      params: {'p_product_id': productId, 'p_quantity': quantity},
    );
  }

  Future<void> removeCartItem(String userId, String productId) async {
    _requireUser(userId);
    await SupabaseConfig.client
        .from('cart_items')
        .delete()
        .eq('user_id', userId)
        .eq('product_id', productId);
  }

  Future<void> clearCart(String userId) async {
    _requireUser(userId);
    await SupabaseConfig.client
        .from('cart_items')
        .delete()
        .eq('user_id', userId);
  }

  Future<List<Map<String, dynamic>>> loadAddresses(String userId) async {
    _requireUser(userId);
    final rows = await SupabaseConfig.client
        .from('user_addresses')
        .select(_addressColumns)
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at');
    return rows.map(addressToApi).toList();
  }

  Future<Map<String, dynamic>> loadDealerProfile(String userId) async {
    _requireUser(userId);
    final row = await SupabaseConfig.client
        .from('users')
        .select(
          'id,email,mobile,name,business_name,owner_name,address,gst_number,'
          'status,is_approved,email_verified,reward_points',
        )
        .eq('id', userId)
        .maybeSingle();
    if (row == null) throw StateError('Dealer profile is unavailable.');
    return profileToApi(Map<String, dynamic>.from(row));
  }

  Future<void> updateDealerProfile(
    String userId,
    Map<String, dynamic> input,
  ) async {
    _requireUser(userId);
    final values = profileUpdateValues(input);
    await SupabaseConfig.client.rpc(
      'ro_update_current_dealer_profile',
      params: {
        'p_name': values['name'],
        'p_mobile': values['mobile'],
        'p_business_name': values['business_name'],
        'p_address': values['address'],
      },
    );
  }

  static Map<String, dynamic> profileToApi(Map<String, dynamic> row) => {
    'id': '${row['id'] ?? ''}',
    'email': '${row['email'] ?? ''}',
    'name': '${row['name'] ?? row['owner_name'] ?? ''}',
    'mobile': '${row['mobile'] ?? ''}',
    'business': '${row['business_name'] ?? ''}',
    'address': '${row['address'] ?? ''}',
    'gstNumber': '${row['gst_number'] ?? ''}',
    'status': '${row['status'] ?? 'pending'}',
    'isApproved': row['is_approved'] == true,
  };

  static Map<String, dynamic> profileUpdateValues(Map<String, dynamic> input) {
    final name = '${input['name'] ?? ''}'.trim();
    final mobile = '${input['mobile'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    final business = '${input['business'] ?? ''}'.trim();
    final address = '${input['address'] ?? ''}'.trim();
    if (name.isEmpty || name.length > 128) {
      throw StateError('Enter a valid name.');
    }
    if (!RegExp(r'^\d{10}$').hasMatch(mobile)) {
      throw StateError('Enter a valid 10-digit mobile number.');
    }
    if (business.length > 191 || address.length > 10000) {
      throw StateError('Profile details are too long.');
    }
    return {
      'name': name,
      'owner_name': name,
      'mobile': mobile,
      'business_name': business.isEmpty ? '$name Aqua Wholesale' : business,
      'address': address,
    };
  }

  Future<String> saveAddress(String userId, Map<String, dynamic> input) async {
    _requireUser(userId);
    final id = '${input['id'] ?? ''}'.trim().isNotEmpty
        ? '${input['id']}'
        : _newAddressId();
    final fullName = '${input['fullName'] ?? ''}'.trim();
    final phone = '${input['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    final street = '${input['street'] ?? ''}'.trim();
    final city = '${input['city'] ?? ''}'.trim();
    final state = '${input['state'] ?? ''}'.trim();
    final pincode = '${input['pincode'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (fullName.isEmpty ||
        phone.length != 10 ||
        street.isEmpty ||
        city.isEmpty ||
        state.isEmpty ||
        pincode.length != 6) {
      throw StateError(
        'Enter a complete address with valid phone and PIN code.',
      );
    }
    final isDefault = input['isDefault'] == true;
    final savedId = await SupabaseConfig.client.rpc(
      'ro_save_dealer_address',
      params: {
        'p_id': id,
        'p_label': '${input['addressType'] ?? 'Office'}',
        'p_business_name': '${input['businessName'] ?? ''}',
        'p_street': street,
        'p_city': city,
        'p_state': state,
        'p_pincode': pincode,
        'p_phone': phone,
        'p_full_name': fullName,
        'p_door_no': '${input['doorNo'] ?? ''}',
        'p_area': '${input['area'] ?? ''}',
        'p_district': '${input['district'] ?? city}',
        'p_landmark': '${input['landmark'] ?? ''}',
        'p_address_type': '${input['addressType'] ?? 'Office'}',
        'p_gst_number': '${input['gstNumber'] ?? ''}'.trim().toUpperCase(),
        'p_make_default': isDefault,
      },
    );
    if (savedId == null || '$savedId'.isEmpty) {
      throw StateError('Address could not be saved.');
    }
    return '$savedId';
  }

  Future<void> setDefaultAddress(String userId, String addressId) async {
    _requireUser(userId);
    if (addressId.isEmpty) throw StateError('Select a saved address.');
    await SupabaseConfig.client.rpc(
      'ro_set_default_dealer_address',
      params: {'p_address_id': addressId},
    );
  }

  Future<void> deleteAddress(String userId, String addressId) async {
    _requireUser(userId);
    await SupabaseConfig.client
        .from('user_addresses')
        .delete()
        .eq('user_id', userId)
        .eq('id', addressId);
  }

  Future<List<Map<String, dynamic>>> loadOrders(
    String userId,
    String email,
  ) async {
    _requireUser(userId);
    final client = SupabaseConfig.client;
    const orderColumns =
        'order_id,user_id,user_email,user_name,user_business,subtotal,discount,gst,delivery_fee,grand_total,payment_status,payment_method,billing_address,company_name,gstin,pan_number,same_as_delivery,delivery_address,delivery_note,status,invoice_number,created_at';
    const itemColumns =
        'id,order_id,product_id,product_name,brand,unit_price,quantity,moq,img_src,sku';
    final byId = await client
        .from('orders')
        .select(orderColumns)
        .eq('user_id', userId);
    // Some older orders may have a null user_id. The policy permits the
    // authenticated email to read those rows, so query that path separately.
    final byEmail = email.trim().isEmpty
        ? <Map<String, dynamic>>[]
        : await client
              .from('orders')
              .select(orderColumns)
              .eq('user_email', email.trim().toLowerCase());
    final orderMap = <String, Map<String, dynamic>>{};
    for (final row in [...byId, ...byEmail]) {
      final order = Map<String, dynamic>.from(row);
      orderMap['${order['order_id']}'] = order;
    }
    if (orderMap.isEmpty) return const [];
    final orderIds = orderMap.keys.toList();
    final itemRows = await client
        .from('order_items')
        .select(itemColumns)
        .inFilter('order_id', orderIds)
        .order('id');
    final itemsByOrder = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final item = Map<String, dynamic>.from(row);
      (itemsByOrder['${item['order_id']}'] ??= []).add(orderItemToApi(item));
    }
    final result = orderMap.values.map((row) {
      return orderToApi(row, itemsByOrder['${row['order_id']}'] ?? const []);
    }).toList();
    result.sort(
      (a, b) => _date(b['createdAt']).compareTo(_date(a['createdAt'])),
    );
    return result;
  }

  Future<Map<String, dynamic>> loadRewards(String userId) async {
    _requireUser(userId);
    final client = SupabaseConfig.client;
    final userRows = await client
        .from('users')
        .select('reward_points')
        .eq('id', userId)
        .maybeSingle();
    final historyRows = await client
        .from('rewards_history')
        .select('id,order_id,order_amount,points_earned,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rewardsToApi(userRows ?? const {}, historyRows);
  }

  Future<Map<String, dynamic>> loadGstInvoices(
    String userId,
    String email,
  ) async {
    _requireUser(userId);
    const columns =
        'order_id,user_id,user_email,grand_total,gst,invoice_number,created_at,with_gst';
    final client = SupabaseConfig.client;
    final byId = await client
        .from('orders')
        .select(columns)
        .eq('user_id', userId)
        .eq('with_gst', true);
    final normalizedEmail = email.trim().toLowerCase();
    final byEmail = normalizedEmail.isEmpty
        ? <Map<String, dynamic>>[]
        : await client
              .from('orders')
              .select(columns)
              .eq('user_email', normalizedEmail)
              .isFilter('user_id', null)
              .eq('with_gst', true);
    final rowsById = <String, Map<String, dynamic>>{};
    for (final row in [...byId, ...byEmail]) {
      final invoice = Map<String, dynamic>.from(row);
      rowsById['${invoice['order_id']}'] = invoice;
    }
    return gstInvoicesToApi(rowsById.values.toList());
  }

  Future<void> createSupportTicket(
    String userId,
    String email,
    Map<String, dynamic> body,
  ) async {
    _requireUser(userId);
    final message = '${body['message'] ?? ''}'.trim();
    if (email.trim().isEmpty || message.isEmpty) {
      throw StateError('Email and message are required.');
    }
    // Identity and email are derived from the signed Supabase session by the
    // RPC. The client cannot forge ticket ownership or set its status.
    await SupabaseConfig.client.rpc(
      'ro_create_support_ticket',
      params: {
        'p_subject': '${body['subject'] ?? body['category'] ?? 'Dealer Query'}',
        'p_message': message,
      },
    );
  }

  static Map<String, dynamic> addressToApi(Map row) => {
    'id': '${row['id'] ?? ''}',
    'label': '${row['label'] ?? row['address_type'] ?? 'Address'}',
    'fullName': '${row['full_name'] ?? ''}',
    'phone': '${row['phone'] ?? ''}',
    'businessName': '${row['business_name'] ?? ''}',
    'doorNo': '${row['door_no'] ?? ''}',
    'street': '${row['street'] ?? ''}',
    'area': '${row['area'] ?? ''}',
    'city': '${row['city'] ?? ''}',
    'district': '${row['district'] ?? ''}',
    'state': '${row['state'] ?? ''}',
    'pincode': '${row['pincode'] ?? ''}',
    'landmark': '${row['landmark'] ?? ''}',
    'addressType': '${row['address_type'] ?? 'Office'}',
    'gstNumber': '${row['gst_number'] ?? ''}',
    'isDefault': row['is_default'] == true,
  };

  static List<CartItemModel> cartRowsToModels(
    List cartRows,
    List productRows,
    List<ProductModel> cachedProducts,
  ) {
    final products = <String, ProductModel>{
      for (final row in productRows)
        '${row['id']}': ProductModel.fromJson(Map<String, dynamic>.from(row)),
    };
    for (final product in cachedProducts) {
      products.putIfAbsent(product.id, () => product);
    }
    return [
      for (final raw in cartRows)
        if (raw is Map)
          CartItemModel(
            product:
                products['${raw['product_id']}'] ??
                _unavailableProduct('${raw['product_id']}'),
            quantity: _int(raw['quantity'], fallback: 1),
          ),
    ];
  }

  static Map<String, dynamic> orderItemToApi(Map row) {
    final price = _double(row['unit_price']);
    return {
      'id': row['product_id'],
      'name': '${row['product_name'] ?? ''}',
      'brand': '${row['brand'] ?? 'RO Wholesale'}',
      'price': '\u20B9${price.toStringAsFixed(2)}',
      'numericPrice': price,
      'quantity': _int(row['quantity'], fallback: 1),
      'moq': '${row['moq'] ?? ''}',
      'imgSrc': '${row['img_src'] ?? ''}',
      'sku': '${row['sku'] ?? row['product_id'] ?? ''}',
    };
  }

  static Map<String, dynamic> orderToApi(
    Map row,
    List<Map<String, dynamic>> items,
  ) => {
    'orderId': '${row['order_id'] ?? ''}',
    'userEmail': '${row['user_email'] ?? ''}',
    'userName': '${row['user_name'] ?? ''}',
    'userBusiness': '${row['user_business'] ?? ''}',
    'items': items,
    'subtotal': _double(row['subtotal']),
    'discount': _double(row['discount']),
    'gst': _double(row['gst']),
    'deliveryFee': _double(row['delivery_fee']),
    'grandTotal': _double(row['grand_total']),
    'paymentMethod': '${row['payment_method'] ?? ''}',
    'paymentStatus': '${row['payment_status'] ?? ''}',
    'deliveryAddress': row['delivery_address'],
    'billingAddress': row['billing_address'] ?? row['delivery_address'],
    'sameAsDelivery': row['same_as_delivery'] == true,
    'companyName': '${row['company_name'] ?? row['user_business'] ?? ''}',
    'gstin': '${row['gstin'] ?? ''}',
    'panNumber': '${row['pan_number'] ?? ''}',
    'deliveryNote': '${row['delivery_note'] ?? ''}',
    'status': '${row['status'] ?? 'Pending'}',
    'invoiceNumber': '${row['invoice_number'] ?? ''}',
    'createdAt': _date(row['created_at']).toIso8601String(),
  };

  static Map<String, dynamic> rewardsToApi(Map user, List rows) {
    final history = rows.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return {
        'orderId': '${row['order_id'] ?? ''}',
        'orderAmount': _double(row['order_amount']),
        'pointsEarned': _int(row['points_earned']),
        'createdAt': _date(row['created_at']).toIso8601String(),
        'description': row['order_id'] == null
            ? 'Reward activity'
            : 'Order ${row['order_id']}',
      };
    }).toList();
    return {
      'totalPoints': _int(user['reward_points']),
      'totalPointsEarned': history.fold<int>(
        0,
        (sum, entry) => sum + _int(entry['pointsEarned']),
      ),
      'history': history,
    };
  }

  static Map<String, dynamic> gstInvoicesToApi(
    List<Map<String, dynamic>> rows,
  ) {
    final invoices = rows.where((row) => row['with_gst'] == true).toList()
      ..sort(
        (a, b) => _date(b['created_at']).compareTo(_date(a['created_at'])),
      );
    // Preserve the current Express rule pending a real credit-policy source.
    const creditLimit = 250000.0;
    final totalSpent = invoices.fold<double>(
      0,
      (sum, invoice) => sum + _double(invoice['grand_total']),
    );
    const monthNames = [
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
    return {
      'success': true,
      'creditLimit': creditLimit,
      'availableCredit': max(0, creditLimit - (totalSpent % creditLimit)),
      'invoices': invoices.map((invoice) {
        final date = _date(invoice['created_at']);
        return {
          'invoiceNumber': '${invoice['invoice_number'] ?? ''}',
          'orderId': '${invoice['order_id'] ?? ''}',
          'date': '${monthNames[date.month - 1]} ${date.day}, ${date.year}',
          'amount': _double(invoice['grand_total']),
          'gstAmount': _double(invoice['gst']),
          'itemsSummary': 'RO Water Equipment',
        };
      }).toList(),
    };
  }

  static int _int(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static double _double(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static DateTime _date(dynamic value) =>
      DateTime.tryParse('${value ?? ''}')?.toLocal() ?? DateTime(1970);

  static String _newAddressId() =>
      'ADDR_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

  static String _pendingCartAddKey(
    String userId,
    String productId,
    int quantity,
  ) =>
      '$_pendingCartAddPrefix:${Uri.encodeComponent(userId)}:'
      '${Uri.encodeComponent(productId)}:$quantity';

  static String _newRequestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static ProductModel _unavailableProduct(String productId) => ProductModel(
    id: productId,
    name: 'Unavailable product',
    sku: productId,
    categoryId: '',
    categoryName: '',
    brand: '',
    mrp: 0,
    dealerPrice: 0,
    imageUrl: '',
    stockStatus: StockStatus.outOfStock,
    moq: 1,
    description: 'This item is no longer available. Remove it before checkout.',
  );

  static void _requireUser(String userId) {
    if (userId.isEmpty) {
      throw StateError('Sign in to access your account data.');
    }
  }
}
