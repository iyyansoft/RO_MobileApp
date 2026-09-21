import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'config/router/app_router.dart';

class RoWholesaleApp extends ConsumerWidget {
  const RoWholesaleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RO Wholesale Dealer App',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Dynamically supports user theme mode preference
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
