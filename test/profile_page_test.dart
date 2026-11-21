import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/features/auth/domain/models/user_model.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:ro_wholesale_dealer_app/features/profile/presentation/widgets/profile_sections.dart';

const _longName = 'Priya Venkatakrishnan Subramaniam Rajagopalan';
const _longEmail =
    'priya.venkatakrishnan.subramaniam.dealer.account@example-wholesale.test';

class _SignedIn extends AuthNotifier {
  _SignedIn(super.api) {
    state = AuthState(
      isLoggedIn: true,
      sessionChecked: true,
      currentUser: UserModel.fromJson({
        'id': 'dealer-1',
        'name': _longName,
        'email': _longEmail,
        'mobile': '9025725248',
        'business': 'Neero Plus Water Solutions',
        'gstNumber': '27AAPFU0939F1ZV',
        'address': '12 Anna Salai, Chennai, Tamil Nadu 600002',
        'status': 'approved',
      }),
    );
  }
}

/// GET /api/user/rewards in the server's shape (rewards.js rewardSummary).
Map<String, dynamic> _lockedRewards() => {
  'success': true,
  'totalPoints': 2345.5,
  'availablePoints': 2345.5,
  'availableValue': 2345.5,
  'totalPointsEarned': 2446,
  'totalPointsRedeemed': 0,
  'pendingRedemption': 100.5,
  'eligiblePurchaseAmount': 71338,
  'freeClaimThreshold': 100000,
  'remainingForFreeClaim': 28662,
  'freeClaimUnlocked': false,
  'pointValueInr': 1,
  'history': [
    {
      'id': 9,
      'type': 'redeemed',
      'orderId': null,
      'orderAmount': 0,
      'pointsEarned': 0,
      'pointsRedeemed': 100.5,
      'status': 'pending',
      'createdAt': '2026-10-25T10:00:00.000Z',
    },
    {
      'id': 8,
      'type': 'earned',
      'orderId': 'K7Q2ZP',
      'orderDate': '2026-10-21T10:00:00.000Z',
      'orderAmount': 14850.5,
      'pointsEarned': 371.26,
      'pointsRedeemed': 0,
      'status': 'credited',
      'createdAt': '2026-10-21T10:00:00.000Z',
    },
    {
      'id': 7,
      'type': 'reversed',
      'orderId': 'R9D3LS',
      'orderDate': '2026-10-01T10:00:00.000Z',
      'orderAmount': -900,
      'pointsEarned': -22.5,
      'pointsRedeemed': 0,
      'status': 'reversed',
      'createdAt': '2026-10-03T10:00:00.000Z',
    },
    {
      'id': 6,
      'type': 'earned',
      'orderId': 'R9D3LS',
      'orderDate': '2026-10-01T10:00:00.000Z',
      'orderAmount': 900,
      'pointsEarned': 22.5,
      'pointsRedeemed': 0,
      'status': 'reversed',
      'createdAt': '2026-10-01T10:00:00.000Z',
    },
    {
      'id': 5,
      'type': 'earned',
      'orderId': 'T2F6HV',
      'orderDate': '2026-08-20T10:00:00.000Z',
      'orderAmount': 500,
      'pointsEarned': 12.5,
      'pointsRedeemed': 0,
      'status': 'credited',
      'createdAt': '2026-08-20T10:00:00.000Z',
    },
  ],
};

Map<String, dynamic> _rewards = _lockedRewards();
final _posts = <(String, Object?)>[];

/// Backend responses in the real API shape.
Map<String, dynamic> _respond(String path) {
  if (path.contains('user/addresses')) {
    return {
      'success': true,
      'addresses': [
        {
          'id': 'a1',
          'label': 'Main warehouse',
          'street': '12 Anna Salai',
          'city': 'Chennai',
          'state': 'Tamil Nadu',
          'pincode': '600002',
          'isDefault': true,
        },
        {
          'id': 'a2',
          'addressType': 'Office',
          'street': '45 MG Road',
          'city': 'Bengaluru',
          'state': 'Karnataka',
          'pincode': '560001',
          'isDefault': false,
        },
      ],
    };
  }
  if (path.contains('user/rewards/claim')) {
    return {'success': true, 'message': 'Claim for 50 points sent.'};
  }
  if (path.contains('user/rewards')) return _rewards;
  if (path.contains('user/gst-invoices')) {
    return {
      'success': true,
      'creditLimit': 250000,
      'availableCredit': 212500,
      'invoices': [
        {
          'invoiceNumber': 'INV-1',
          'orderId': 'K7Q2ZP',
          'date': 'Oct 21, 2026',
          'amount': 14850.5,
          'gstAmount': 2265.33,
        },
      ],
    };
  }
  return {'success': true};
}

Future<GlobalKey> _pump(WidgetTester tester, double width) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  final api = ApiClient(
    interceptors: [
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.method == 'POST')
            _posts.add((request.path, request.data));
          handler.resolve(
            Response(requestOptions: request, data: _respond(request.path)),
          );
        },
      ),
    ],
  );
  final key = GlobalKey();
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      for (final page in ['orders', 'login', 'wishlist'])
        GoRoute(
          path: '/$page',
          builder: (_, __) =>
              Scaffold(body: Text('${page.toUpperCase()} PAGE')),
        ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authProvider.overrideWith((ref) => _SignedIn(api)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        // Screenshots use a plain theme so the locally loaded font applies
        // (the app's Google Font can't be downloaded inside tests).
        theme: Platform.environment['PREVIEW_FONT'] != null
            ? ThemeData(useMaterial3: true)
            : AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => RepaintBoundary(key: key, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  final previewDir = Platform.environment['PREVIEW_DIR'];
  final previewFont = Platform.environment['PREVIEW_FONT'];

  setUpAll(() async {
    if (previewFont != null && File(previewFont).existsSync()) {
      for (final family in ['Roboto', 'Outfit']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(previewFont).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    }
  });

  for (final (label, width) in [
    ('desktop', 1440.0),
    ('tablet', 820.0),
    ('mobile', 390.0),
  ]) {
    testWidgets('profile page on $label shows real data without overflow', (
      tester,
    ) async {
      final key = await _pump(tester, width);
      expect(tester.takeException(), isNull);

      // Summary.
      expect(find.text(_longName), findsOneWidget);
      expect(find.text(_longEmail), findsOneWidget);
      expect(find.text('9025725248'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-edit')), findsOneWidget);
      // Long name/email stay inside the screen.
      for (final f in [find.text(_longName), find.text(_longEmail)]) {
        final r = tester.getRect(f);
        expect(r.right, lessThanOrEqualTo(width), reason: 'text fits');
      }

      // Rewards: balance + ₹ value, totals, Free Claim progress, history.
      expect(find.text('2,345.50'), findsOneWidget);
      expect(find.text('Worth ₹2,345.50'), findsOneWidget);
      expect(find.text('2,446 pts'), findsOneWidget, reason: 'total earned');
      expect(find.text('0 pts'), findsOneWidget, reason: 'total redeemed');
      expect(find.text('100.50 pts awaiting claim approval'), findsOneWidget);
      expect(find.text('Not yet eligible'), findsOneWidget);
      expect(find.text('Free Claim progress'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
      expect(find.text('₹71,338.00 of ₹1,00,000 in purchases'), findsOneWidget);
      expect(
        find.text(
          'Purchase ₹28,662.00 more to unlock Free Claim.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('reward-progress')),
            )
            .value,
        closeTo(0.71338, 1e-9),
      );
      expect(find.byKey(const ValueKey('reward-claim')), findsNothing);
      expect(find.text('Free Claim request'), findsOneWidget);
      expect(find.text('−100.50 pts'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Earned on order #K7Q2ZP'), findsOneWidget);
      expect(find.text('+371.26 pts'), findsOneWidget);
      expect(find.text('21 Oct 2026  •  Order ₹14,850.50'), findsOneWidget);
      expect(find.text('Reversed: order #R9D3LS cancelled'), findsOneWidget);
      expect(find.text('−22.50 pts'), findsOneWidget);
      expect(find.text('+12.50 pts'), findsNothing, reason: '4 shown');
      await tester.tap(find.text('View all 5 reward activities'));
      await tester.pumpAndSettle();
      expect(find.text('+12.50 pts'), findsOneWidget);
      expect(find.text('Reversed'), findsNWidgets(2));
      expect(find.text('Credited'), findsNWidgets(2));

      // Credit: available, limit, used and progress from the backend.
      expect(find.byKey(const ValueKey('credit-available')), findsOneWidget);
      expect(find.text('₹2,12,500.00'), findsNWidgets(2));
      expect(find.text('₹2,50,000.00'), findsOneWidget);
      expect(find.text('Used (15%)'), findsOneWidget);
      expect(find.text('₹37,500.00'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('credit-progress')),
      );
      expect(bar.value, closeTo(0.15, 0.0001));

      // Business info, addresses, invoices and options.
      expect(find.text('27AAPFU0939F1ZV'), findsOneWidget);
      expect(find.text('Main warehouse'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Order #K7Q2ZP'), findsOneWidget);
      expect(find.text('₹14,850.50'), findsOneWidget);
      expect(find.text('My orders'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-sign-out')), findsOneWidget);

      // Layout: desktop = two columns (rewards left, credit right);
      // tablet/phone = stacked (credit below rewards).
      final rewards = tester.getRect(
        find.widgetWithText(ProfileSectionCard, 'Reward Points'),
      );
      final credit = tester.getRect(
        find.widgetWithText(ProfileSectionCard, 'Available Credit'),
      );
      if (width >= 900) {
        expect(credit.left, greaterThan(rewards.right));
        expect((credit.top - rewards.top).abs(), lessThan(1));
      } else {
        expect(credit.top, greaterThan(rewards.bottom));
        expect((credit.left - rewards.left).abs(), lessThan(1));
      }
      // Every card fits horizontally.
      for (final e in find.byType(ProfileSectionCard).evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);

      if (previewDir != null) {
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$previewDir/profile_$label.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('existing actions still work', (tester) async {
    await _pump(tester, 1440);

    await tester.tap(find.byKey(const ValueKey('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('address-add')));
    await tester.pumpAndSettle();
    expect(find.text('Add address'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Address actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Set default'), findsNothing); // first is default
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My orders'));
    await tester.pumpAndSettle();
    expect(find.text('ORDERS PAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1 paisa short of ₹1,00,000: still locked, no claim', (tester) async {
    _rewards = {
      ..._lockedRewards(),
      'eligiblePurchaseAmount': 99999.99,
      'remainingForFreeClaim': 0.01,
    };
    addTearDown(() => _rewards = _lockedRewards());
    await _pump(tester, 390);
    expect(find.text('Free Claim progress'), findsOneWidget);
    expect(
      find.text(
        'Purchase ₹0.01 more to unlock Free Claim.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reward-claim')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1440.0, 390.0]) {
    testWidgets('Free Claim unlocked at ₹1,00,000: claim points ($width)', (
      tester,
    ) async {
      _rewards = {
        ..._lockedRewards(),
        'eligiblePurchaseAmount': 100000,
        'remainingForFreeClaim': 0,
        'freeClaimUnlocked': true,
        'pendingRedemption': 0,
      };
      _posts.clear();
      addTearDown(() => _rewards = _lockedRewards());
      await _pump(tester, width);
      expect(find.text('Free Claim Unlocked'), findsOneWidget);
      expect(find.text('Eligible'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(
        find.text('Redeem up to 2,345.50 pts (₹2,345.50).'),
        findsOneWidget,
      );
      expect(
        find.textContaining('more to unlock', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      final claim = find.byKey(const ValueKey('reward-claim'));
      await tester.ensureVisible(claim);
      await tester.tap(claim);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('reward-claim-points'));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '2345.50',
      );
      final send = find.byKey(const ValueKey('reward-claim-submit'));
      for (final (input, error) in [
        ('5000', 'You have 2,345.50 pts.'),
        ('1.234', 'Enter points, up to 2 decimals.'),
        ('0', 'Enter more than 0 points.'),
      ]) {
        await tester.enterText(field, input);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(find.text(error), findsOneWidget, reason: input);
      }
      expect(_posts, isEmpty, reason: 'invalid claims are not sent');
      await tester.enterText(field, '50');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(_posts.single.$1, contains('user/rewards/claim'));
      expect(_posts.single.$2, {'points': 50.0});
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }
}
