import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/registration_provider.dart';

class DealerRegistrationScreen extends ConsumerStatefulWidget {
  const DealerRegistrationScreen({super.key});

  @override
  ConsumerState<DealerRegistrationScreen> createState() => _DealerRegistrationScreenState();
}

class _DealerRegistrationScreenState extends ConsumerState<DealerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _businessNameController = TextEditingController(text: 'Aqua Tech Water Solutions');
  final _ownerNameController = TextEditingController(text: 'Rajesh Kumar');
  final _mobileController = TextEditingController(text: '9876543210');
  final _emailController = TextEditingController(text: 'rajesh@aquatech.com');
  final _addressController = TextEditingController(text: 'Plot 42, Industrial Area Phase 2');
  final _cityController = TextEditingController(text: 'Mumbai');
  final _stateController = TextEditingController(text: 'Maharashtra');
  final _pincodeController = TextEditingController(text: '400072');
  final _gstController = TextEditingController(text: '27AABCU9603R1ZM');
  final _panController = TextEditingController(text: 'ABCDE1234F');

  String _selectedBusinessType = 'Proprietorship';
  String _selectedDealerType = 'Wholesale Dealer';

  final List<String> _businessTypes = [
    'Proprietorship',
    'Partnership',
    'Private Limited',
    'LLP',
  ];

  final List<String> _dealerTypes = [
    'Retailer',
    'Wholesale Dealer',
    'Distributor',
    'System Integrator',
  ];

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _gstController.dispose();
    _panController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState?.validate() ?? false) {
      final success = await ref.read(registrationProvider.notifier).submitRegistration(
            businessName: _businessNameController.text.trim(),
            ownerName: _ownerNameController.text.trim(),
            mobile: _mobileController.text.trim(),
            email: _emailController.text.trim(),
            address: _addressController.text.trim(),
            city: _cityController.text.trim(),
            stateName: _stateController.text.trim(),
            pincode: _pincodeController.text.trim(),
            gstNumber: _gstController.text.trim(),
            panNumber: _panController.text.trim(),
            businessType: _selectedBusinessType,
            dealerType: _selectedDealerType,
          );

      if (success && mounted) {
        context.push('/registration-submitted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final regState = ref.watch(registrationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('B2B Dealer Registration'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Intro Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primaryColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: primaryColor, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Complete dealer profile to unlock tier 1 wholesale pricing & GST tax benefits.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('Business Information', isDark),
                const SizedBox(height: 12),
                _buildTextField('Business / Shop Name *', _businessNameController, isDark),
                _buildTextField('Owner / Proprietor Name *', _ownerNameController, isDark),
                Row(
                  children: [
                    Expanded(child: _buildDropdown('Business Type', _selectedBusinessType, _businessTypes, (val) => setState(() => _selectedBusinessType = val!), isDark)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDropdown('Dealer Type', _selectedDealerType, _dealerTypes, (val) => setState(() => _selectedDealerType = val!), isDark)),
                  ],
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Contact & Address Details', isDark),
                const SizedBox(height: 12),
                _buildTextField('Mobile Number *', _mobileController, isDark, inputType: TextInputType.phone),
                _buildTextField('Email Address *', _emailController, isDark, inputType: TextInputType.emailAddress),
                _buildTextField('Full Business Address *', _addressController, isDark, maxLines: 2),
                Row(
                  children: [
                    Expanded(child: _buildTextField('City *', _cityController, isDark)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTextField('State *', _stateController, isDark)),
                  ],
                ),
                _buildTextField('Pincode *', _pincodeController, isDark, inputType: TextInputType.number),

                const SizedBox(height: 24),
                _buildSectionHeader('Taxation & Legal Details', isDark),
                const SizedBox(height: 12),
                _buildTextField('GSTIN Number (15 Digits) *', _gstController, isDark),
                _buildTextField('PAN Card Number *', _panController, isDark),

                const SizedBox(height: 24),
                _buildSectionHeader('Document Upload (KYC)', isDark),
                const SizedBox(height: 4),
                const Text(
                  'Upload clear PDF or image copies for verification.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const SizedBox(height: 14),

                // 4 Document Upload Cards
                _buildDocUploadCard('GST Certificate', isDark, primaryColor, regState),
                _buildDocUploadCard('PAN Card', isDark, primaryColor, regState),
                _buildDocUploadCard('Business Proof (Trade License)', isDark, primaryColor, regState),
                _buildDocUploadCard('Address Proof (Utility Bill)', isDark, primaryColor, regState),

                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: regState.isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: regState.isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Submit Dealer Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              Icon(Icons.send_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isDark, {TextInputType inputType = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: inputType,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        validator: (val) {
          if (val == null || val.trim().isEmpty) {
            return '$label is required';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDocUploadCard(String docType, bool isDark, Color primaryColor, RegistrationState regState) {
    final progress = regState.uploadProgressMap[docType] ?? 0.0;
    final fileName = regState.uploadedFilesMap[docType];
    final isUploaded = progress >= 1.0 || fileName != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUploaded ? const Color(0xFF10B981) : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0)),
          width: isUploaded ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isUploaded ? Icons.task_alt_rounded : Icons.cloud_upload_outlined,
                    color: isUploaded ? const Color(0xFF10B981) : primaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    docType,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: () {
                  ref.read(registrationProvider.notifier).simulateFileUpload(docType);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(isUploaded ? 'Re-upload' : 'Upload'),
              ),
            ],
          ),

          // Upload Progress Bar
          if (progress > 0.0 && progress < 1.0) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 4),
            Text('Uploading... ${(progress * 100).round()}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],

          // Uploaded File Chip
          if (isUploaded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    fileName ?? '${docType.toLowerCase().replaceAll(' ', '_')}.pdf',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
