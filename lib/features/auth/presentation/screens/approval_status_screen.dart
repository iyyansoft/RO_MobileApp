import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/dealer_registration_model.dart';
import '../providers/registration_provider.dart';

class ApprovalStatusScreen extends ConsumerWidget {
  const ApprovalStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final regData = ref.watch(registrationProvider).data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Approval Status'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Status updated from B2B Server.')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Interactive Demo State Switcher Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildStateTab(context, ref, 'Pending', ApprovalStatus.pending, regData.status),
                  _buildStateTab(context, ref, 'Approved', ApprovalStatus.approved, regData.status),
                  _buildStateTab(context, ref, 'Rejected', ApprovalStatus.rejected, regData.status),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (regData.status == ApprovalStatus.pending)
                      _buildPendingView(context, isDark, primaryColor, regData),
                    if (regData.status == ApprovalStatus.approved)
                      _buildApprovedView(context, isDark, primaryColor, regData),
                    if (regData.status == ApprovalStatus.rejected)
                      _buildRejectedView(context, isDark, primaryColor, regData),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateTab(BuildContext context, WidgetRef ref, String label, ApprovalStatus status, ApprovalStatus currentStatus) {
    final isSelected = currentStatus == status;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(registrationProvider.notifier).setApprovalStatus(status);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // 1. Pending View
  Widget _buildPendingView(BuildContext context, bool isDark, Color primaryColor, DealerRegistrationModel data) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.hourglass_top_rounded, size: 44, color: Color(0xFFF59E0B)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Verification Under Review',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Our GST & B2B compliance team is validating your trade license. Estimated completion time is 24-48 hours.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
        ),
        const SizedBox(height: 24),

        // Verification Steps Timeline
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildTimelineStep('1. Application Submitted', data.submittedDate, isDone: true, isDark: isDark),
              _buildTimelineDivider(isDone: true),
              _buildTimelineStep('2. GST & PAN Verification', 'In Progress...', isCurrent: true, isDark: isDark),
              _buildTimelineDivider(isDone: false),
              _buildTimelineStep('3. Wholesale Credit Limit Assignment', 'Pending', isDone: false, isDark: isDark),
            ],
          ),
        ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Browse Wholesale Catalog Demo'),
          ),
        ),
      ],
    );
  }

  // 2. Approved View
  Widget _buildApprovedView(BuildContext context, bool isDark, Color primaryColor, DealerRegistrationModel data) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.verified_rounded, size: 48, color: Color(0xFF10B981)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Dealer Account Approved! 🎉',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Congratulations ${data.ownerName}! ${data.businessName} is officially verified for tier 1 wholesale pricing.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
        ),
        const SizedBox(height: 24),

        // Approved Dealer Perks Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF051838), Color(0xFF0D3E9D)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D3E9D).withOpacity(0.3),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dealer Tier Status', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'GOLD DEALER',
                      style: TextStyle(color: Color(0xFF051838), fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              _buildApprovedPerk(Icons.percent_rounded, 'Exclusive 25% Dealer Discount Active'),
              const SizedBox(height: 10),
              _buildApprovedPerk(Icons.receipt_long_rounded, 'GST Input Tax Invoices Enabled'),
              const SizedBox(height: 10),
              _buildApprovedPerk(Icons.local_shipping_rounded, 'Priority Dispatch & Credit Terms Enabled'),
            ],
          ),
        ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/home'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.shopping_bag_rounded),
            label: const Text('Start Wholesale Ordering', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // 3. Rejected View
  Widget _buildRejectedView(BuildContext context, bool isDark, Color primaryColor, DealerRegistrationModel data) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.gpp_bad_rounded, size: 48, color: Color(0xFFEF4444)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Application Rejected',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your dealer verification application requires modification before approval.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
        ),
        const SizedBox(height: 24),

        // Rejection Reason Box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 18),
                  SizedBox(width: 8),
                  Text('Reason for Rejection:', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data.rejectionReason ?? 'GST Certificate document image is blurry or name mismatch.',
                style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : const Color(0xFF0F172A), height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              context.push('/register');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Update Details & Resubmit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep(String title, String subtitle, {bool isDone = false, bool isCurrent = false, required bool isDark}) {
    Color color = isDone ? const Color(0xFF10B981) : (isCurrent ? const Color(0xFFF59E0B) : Colors.grey);
    return Row(
      children: [
        Icon(isDone ? Icons.check_circle_rounded : (isCurrent ? Icons.access_time_filled_rounded : Icons.circle_outlined), color: color, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0F172A))),
            Text(subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineDivider({required bool isDone}) {
    return Container(
      margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      alignment: Alignment.centerLeft,
      height: 20,
      width: 2,
      color: isDone ? const Color(0xFF10B981) : Colors.grey.withOpacity(0.3),
    );
  }

  Widget _buildApprovedPerk(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00F5D4), size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
