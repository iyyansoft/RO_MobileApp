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
import '../../../features/home/presentation/screens/home_screen.dart';
import '../../../features/products/presentation/screens/product_details_screen.dart';
import '../../../features/products/presentation/screens/products_screen.dart';
import '../../../features/orders/presentation/screens/orders_screen.dart';
import '../../../features/profile/presentation/screens/profile_screen.dart';
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
        '/orders',
        '/profile',
        '/cart',
        '/checkout',
      ];
      if (protected.any(
        (path) => state.uri.path == path || state.uri.path.startsWith('$path/'),
      )) {
        final auth = ProviderScope.containerOf(context).read(authProvider);
        if (!auth.isLoggedIn) return '/login';
      }
      return null;
    },
    routes: [
      // 1. Auth & Onboarding Routes
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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

      // 3. Shopping Cart & Checkout Routes
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
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
            path: '/orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
}
