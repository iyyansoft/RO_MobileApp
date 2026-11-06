import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/products/presentation/providers/product_provider.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/auth/presentation/screens/splash_screen.dart';
import '../../../features/auth/presentation/screens/login_screen.dart';
import '../../../features/auth/presentation/screens/otp_verification_screen.dart';
import '../../../features/auth/presentation/screens/dealer_registration_screen.dart';
import '../../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../../features/auth/presentation/screens/registration_submitted_screen.dart';
import '../../../features/auth/presentation/screens/approval_status_screen.dart';
import '../../../features/shop/presentation/shop_screens.dart';
import '../../../features/cart/presentation/screens/cart_screen.dart';
import '../../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../../features/home/presentation/screens/home_screen.dart';
import '../../../features/products/presentation/screens/product_details_screen.dart';
import '../../../features/products/presentation/screens/products_screen.dart';
import '../../../features/products/presentation/screens/wishlist_screen.dart';
import '../../../features/orders/presentation/screens/orders_screen.dart';
import '../../../features/profile/presentation/screens/profile_screen.dart';
import '../../../features/admin/presentation/screens/admin_screen.dart';
import '../../../features/main/presentation/screens/main_navigation_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      const protected = [
        '/home',
        '/products',
        '/categories',
        '/orders',
        '/profile',
        '/cart',
        '/checkout',
        '/order-success',
        '/wishlist',
      ];
      if (protected.any(
        (path) => state.uri.path == path || state.uri.path.startsWith('$path/'),
      )) {
        final auth = ProviderScope.containerOf(context).read(authProvider);
        if (!auth.sessionChecked) {
          // Browser refresh / direct URL: the saved session has not been
          // restored yet. Restore it on the splash screen, then come back to
          // the exact same URL instead of bouncing to Login.
          return Uri(
            path: '/splash',
            queryParameters: {'from': state.uri.toString()},
          ).toString();
        }
        if (!auth.isLoggedIn) return '/login';
      }
      return null;
    },
    routes: [
      // 1. Auth & Onboarding Routes
      GoRoute(
        path: '/splash',
        builder: (context, state) =>
            SplashScreen(returnTo: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          usePassword: state.uri.queryParameters['mode'] == 'password',
        ),
      ),
      GoRoute(
        path: '/shop/login',
        builder: (context, state) => const ShopEmployeeLoginScreen(),
      ),
      GoRoute(
        path: '/shop/app',
        builder: (context, state) => const ShopAppScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) => const OtpVerificationScreen(),
      ),

      // 2. PART 3 Dealer Registration & KYC Approval Routes
      GoRoute(
        path: '/register',
        builder: (context, state) => const DealerRegistrationScreen(),
      ),
      GoRoute(
        path: '/registration-submitted',
        builder: (context, state) => const RegistrationSubmittedScreen(),
      ),
      GoRoute(
        path: '/approval-status',
        builder: (context, state) => const ApprovalStatusScreen(),
      ),

      // Admin Route (Unified Web & Mobile)
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),

      // 3. Shopping Cart & Checkout Routes
      GoRoute(
        path: WishlistScreen.path,
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: OrderSuccessScreen.path,
        redirect: (context, state) =>
            OrderSuccessScreen.fromQuery(state.uri.queryParameters) == null
            ? '/orders'
            : null,
        builder: (context, state) =>
            OrderSuccessScreen.fromQuery(state.uri.queryParameters)!,
      ),

      GoRoute(
        path: '/products/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final productId = state.pathParameters['id'];
          return Consumer(
            builder: (context, ref, child) {
              return ref
                  .watch(catalogProductsProvider)
                  .when(
                    loading: () => const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stack) =>
                        Scaffold(body: Center(child: Text('$error'))),
                    data: (products) {
                      final matches = products.where((p) => p.id == productId);
                      if (matches.isEmpty) {
                        return const Scaffold(
                          body: Center(child: Text('Product not found')),
                        );
                      }
                      return ProductDetailsScreen(product: matches.first);
                    },
                  );
            },
          );
        },
      ),
      // 4. Main App Shell Routes
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainNavigationScreen(child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const ProductsScreen(),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const CartScreen(),
          ),
        ],
      ),
    ],
  );
}
