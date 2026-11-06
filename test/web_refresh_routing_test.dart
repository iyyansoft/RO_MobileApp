import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/splash_screen.dart';

const _savedSession = {
  'id': 'dealer-1',
  'name': 'Dealer',
  'email': 'dealer@example.test',
  'token': 'saved-token',
};

ApiClient _api(void Function(RequestOptions, RequestInterceptorHandler) onReq) =>
    ApiClient(interceptors: [InterceptorsWrapper(onRequest: onReq)]);

void _reply(RequestOptions r, RequestInterceptorHandler h, int status) {
  if (status == 200) {
    h.resolve(
      Response(
        requestOptions: r,
        statusCode: 200,
        data: {'success': true, 'user': _savedSession},
      ),
    );
  } else {
    h.reject(
      DioException(
        requestOptions: r,
        response: Response(
          requestOptions: r,
          statusCode: status,
          data: {'success': false},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient.sessionToken = null;
    FlutterSecureStorage.setMockInitialValues({
      'ro_dealer_session': jsonEncode(_savedSession),
    });
  });

  test('a network failure keeps the saved session (no logout on refresh)',
      () async {
    final auth = AuthNotifier(
      _api(
        (r, h) => h.reject(
          DioException(requestOptions: r, type: DioExceptionType.connectionError),
        ),
      ),
    );
    addTearDown(auth.dispose);
    await auth.restoreSession();
    expect(auth.state.sessionChecked, isTrue);
    expect(auth.state.isLoggedIn, isTrue);
    expect(ApiClient.sessionToken, 'saved-token');
    expect(
      await const FlutterSecureStorage().read(key: 'ro_dealer_session'),
      isNotNull,
    );
  });

  test('a server that is temporarily unavailable (503) keeps the session',
      () async {
    final auth = AuthNotifier(_api((r, h) => _reply(r, h, 503)));
    addTearDown(auth.dispose);
    await auth.restoreSession();
    expect(auth.state.isLoggedIn, isTrue);
  });

  test('an expired session (401) is cleared and marked checked', () async {
    final auth = AuthNotifier(_api((r, h) => _reply(r, h, 401)));
    addTearDown(auth.dispose);
    await auth.restoreSession();
    expect(auth.state.sessionChecked, isTrue);
    expect(auth.state.isLoggedIn, isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'ro_dealer_session'),
      isNull,
    );
  });

  test('concurrent restores share a single session request', () async {
    var calls = 0;
    final auth = AuthNotifier(
      _api((r, h) {
        calls++;
        _reply(r, h, 200);
      }),
    );
    addTearDown(auth.dispose);
    await Future.wait([auth.restoreSession(), auth.restoreSession()]);
    await auth.restoreSession();
    expect(calls, 1);
    expect(auth.state.isLoggedIn, isTrue);
  });

  Future<GoRouter> pumpRefreshAt(
    WidgetTester tester,
    String location,
    int sessionStatus,
  ) async {
    final auth = AuthNotifier(_api((r, h) => _reply(r, h, sessionStatus)));
    // Same redirect rule as AppRouter for protected pages.
    final router = GoRouter(
      initialLocation: location,
      redirect: (context, state) {
        if (!state.uri.path.startsWith('/orders')) return null;
        final a = ProviderScope.containerOf(context).read(authProvider);
        if (!a.sessionChecked) {
          return Uri(
            path: '/splash',
            queryParameters: {'from': state.uri.toString()},
          ).toString();
        }
        return a.isLoggedIn ? null : '/login';
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, s) =>
              SplashScreen(returnTo: s.uri.queryParameters['from']),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('Login page')),
        GoRoute(path: '/home', builder: (_, _) => const Text('Home page')),
        GoRoute(path: '/orders', builder: (_, _) => const Text('Orders page')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  testWidgets('refreshing a protected page returns to the same URL',
      (tester) async {
    final router = await pumpRefreshAt(tester, '/orders?tab=open', 200);
    expect(find.text('Orders page'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/orders?tab=open',
    );
  });

  testWidgets('refreshing with an expired session goes to Login',
      (tester) async {
    await pumpRefreshAt(tester, '/orders', 401);
    expect(find.text('Login page'), findsOneWidget);
  });
}
