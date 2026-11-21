import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../features/products/domain/category_price_view.dart';
import '../../../features/bulk_orders/presentation/screens/bulk_orders_screen.dart';
import '../../../features/bulk_orders/presentation/screens/bulk_product_details_screen.dart';
import '../../../features/products/presentation/screens/products_screen.dart';
import '../../../features/products/presentation/screens/wishlist_screen.dart';
import '../../../features/orders/presentation/screens/orders_screen.dart';
import '../../../features/profile/presentation/screens/profile_screen.dart';
import '../../../features/admin/presentation/screens/admin_screen.dart';
import '../../../features/main/presentation/screens/main_navigation_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
// The customer pages' navigator (inside MainNavigationScreen, which draws
// the navbar); the navbar uses it to close pages opened on top of a tab.
final GlobalKey<NavigatorState> _shellNavigatorKey =
    MainNavigationScreen.shellNavigatorKey;

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // The Admin Dashboard is web-only: never shown in the Android app.
      if (!kIsWeb && state.uri.path.startsWith('/admin')) return '/login';
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

      // Admin Route (web only; the redirect above keeps Android out)
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),

      // 4. Main App Shell Routes
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainNavigationScreen(child: child);
        },
        routes: [
          // Wishlist, checkout, order confirmation and product details are
          // inside the shell too, so the main navbar shows on every page.
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
                          final matches = products.where(
                            (p) => p.id == productId,
                          );
                          if (matches.isEmpty) {
                            return const Scaffold(
                              body: Center(child: Text('Product not found')),
                            );
                          }
                          // ?view=cabinet | ro-systems keeps the category's
                          // price format; no view = the standard display.
                          return ProductDetailsScreen(
                            product: matches.first,
                            priceView: ProductPriceView.fromQuery(
                              state.uri.queryParameters['view'],
                            ),
                          );
                        },
                      );
                },
              );
            },
          ),
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
            path: BulkOrdersScreen.path,
            builder: (context, state) => BulkOrdersScreen(
              initialCategoryId: state.uri.queryParameters['category'],
            ),
            routes: [
              // Bulk Product Details (bulk pricing; ?category= for Back).
              GoRoute(
                path: BulkProductDetailsScreen.routePath,
                builder: (context, state) => BulkProductDetailsScreen(
                  productId: state.pathParameters['id']!,
                  categoryId: state.uri.queryParameters['category'],
                ),
              ),
            ],
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
