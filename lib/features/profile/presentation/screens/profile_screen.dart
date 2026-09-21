import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/error_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _simulateError = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Dealer Profile',
        actions: [
          IconButton(
            icon: Icon(_simulateError ? Icons.person_rounded : Icons.error_outline_rounded),
            onPressed: () {
              setState(() {
                _simulateError = !_simulateError;
              });
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _simulateError ? _buildErrorLayout() : _buildProfileLayout(isDark),
      ),
    );
  }

  Widget _buildErrorLayout() {
    return ErrorState(
      key: const ValueKey('error_layout'),
      title: 'Credit Verification Failed',
      errorMessage: 'We could not fetch your B2B credit and limit information due to a server response timeout.',
      onRetry: () {
        setState(() {
          _simulateError = false;
        });
      },
    );
  }

  Widget _buildProfileLayout(bool isDark) {
    return SingleChildScrollView(
      key: const ValueKey('profile_layout'),
      padding: const EdgeInsets.all(AppTheme.spaceM),
      child: Column(
        children: [
          // Dealer Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceL),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: isDark ? AppColors.secondaryDark.withOpacity(0.2) : AppColors.primaryLight.withOpacity(0.1),
                    child: Icon(
                      Icons.business_rounded,
                      size: 40,
                      color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceM),
                  const Text(
                    'Aqua Tech Water Solutions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Dealer ID: RO-DEL-56294 • GST Verified',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceM),

          // Approval & Verification Navigation Cards
          Card(
            color: isDark ? AppColors.surfaceDark : const Color(0xFFEFF6FF),
            child: ListTile(
              leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF0F62FE)),
              title: const Text('Account Verification Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text('Check approval status (Pending/Approved/Rejected)', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                context.push('/approval-status');
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_add, color: Color(0xFF10B981)),
              title: const Text('New Dealer Registration / KYC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text('Update business details & GST certificates', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                context.push('/register');
              },
            ),
          ),
          const SizedBox(height: AppTheme.spaceS),

          // Business details list
          _buildInfoTile(
            context,
            icon: Icons.credit_card_rounded,
            title: 'Available Credit Limit',
            trailing: '₹5,00,000',
            trailingColor: isDark ? AppColors.accentDark : AppColors.primaryLight,
          ),
          _buildInfoTile(
            context,
            icon: Icons.location_on_rounded,
            title: 'Delivery Address',
            trailing: 'Industrial Area, Phase 2, Mumbai',
          ),
          _buildInfoTile(
            context,
            icon: Icons.verified_rounded,
            title: 'GSTIN Status',
            trailing: 'Verified (27AABCU9603R1ZM)',
            trailingColor: isDark ? AppColors.successDark : AppColors.successLight,
          ),
          _buildInfoTile(
            context,
            icon: Icons.contact_phone_rounded,
            title: 'Account Manager',
            trailing: 'Rohan Sharma (+91 98765 43210)',
          ),
          const SizedBox(height: AppTheme.spaceXL),
          
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppColors.errorDark.withOpacity(0.1) : AppColors.errorLight.withOpacity(0.1),
              foregroundColor: isDark ? AppColors.errorDark : AppColors.errorLight,
              side: BorderSide(color: isDark ? AppColors.errorDark : AppColors.errorLight),
            ),
            onPressed: () {
              context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('LOGOUT ACCOUNT'),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String trailing,
    Color? trailingColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceS),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        trailing: Text(
          trailing,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: trailingColor ?? Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}
