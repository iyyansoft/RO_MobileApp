import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/dealer_registration_model.dart';

class RegistrationState {
  final DealerRegistrationModel data;
  final bool isSubmitting;
  final Map<String, double> uploadProgressMap;
  final Map<String, String> uploadedFilesMap;

  const RegistrationState({
    required this.data,
    this.isSubmitting = false,
    this.uploadProgressMap = const {},
    this.uploadedFilesMap = const {},
  });

  RegistrationState copyWith({
    DealerRegistrationModel? data,
    bool? isSubmitting,
    Map<String, double>? uploadProgressMap,
    Map<String, String>? uploadedFilesMap,
  }) {
    return RegistrationState(
      data: data ?? this.data,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      uploadProgressMap: uploadProgressMap ?? this.uploadProgressMap,
      uploadedFilesMap: uploadedFilesMap ?? this.uploadedFilesMap,
    );
  }
}

class RegistrationNotifier extends StateNotifier<RegistrationState> {
  RegistrationNotifier()
      : super(RegistrationState(data: DealerRegistrationModel.defaultMock));

  Future<void> simulateFileUpload(String docType) async {
    // Simulate progress ticks: 20%, 50%, 85%, 100%
    final currentProgress = Map<String, double>.from(state.uploadProgressMap);
    final currentFiles = Map<String, String>.from(state.uploadedFilesMap);

    currentProgress[docType] = 0.2;
    state = state.copyWith(uploadProgressMap: currentProgress);
    await Future.delayed(const Duration(milliseconds: 300));

    currentProgress[docType] = 0.55;
    state = state.copyWith(uploadProgressMap: currentProgress);
    await Future.delayed(const Duration(milliseconds: 300));

    currentProgress[docType] = 0.9;
    state = state.copyWith(uploadProgressMap: currentProgress);
    await Future.delayed(const Duration(milliseconds: 300));

    currentProgress[docType] = 1.0;
    currentFiles[docType] = '${docType.toLowerCase().replaceAll(' ', '_')}_doc.pdf';
    state = state.copyWith(
      uploadProgressMap: currentProgress,
      uploadedFilesMap: currentFiles,
    );
  }

  Future<bool> submitRegistration({
    required String businessName,
    required String ownerName,
    required String mobile,
    required String email,
    required String address,
    required String city,
    required String stateName,
    required String pincode,
    required String gstNumber,
    required String panNumber,
    required String businessType,
    required String dealerType,
  }) async {
    state = state.copyWith(isSubmitting: true);
    await Future.delayed(const Duration(milliseconds: 1500));

    final newApp = DealerRegistrationModel(
      applicationId: 'APP-2026-${(10000 + (90000 * (DateTime.now().millisecond / 1000)).round())}',
      businessName: businessName,
      ownerName: ownerName,
      mobile: mobile,
      email: email,
      address: address,
      city: city,
      state: stateName,
      pincode: pincode,
      gstNumber: gstNumber,
      panNumber: panNumber,
      businessType: businessType,
      dealerType: dealerType,
      status: ApprovalStatus.pending,
      submittedDate: '03 Sep 2026, 11:23 AM',
      documents: state.uploadedFilesMap.entries.map((e) {
        return UploadedDoc(docType: e.key, fileName: e.value);
      }).toList(),
    );

    state = state.copyWith(
      isSubmitting: false,
      data: newApp,
    );
    return true;
  }

  void setApprovalStatus(ApprovalStatus newStatus, {String? rejectionReason}) {
    final updatedData = DealerRegistrationModel(
      applicationId: state.data.applicationId,
      businessName: state.data.businessName,
      ownerName: state.data.ownerName,
      mobile: state.data.mobile,
      email: state.data.email,
      address: state.data.address,
      city: state.data.city,
      state: state.data.state,
      pincode: state.data.pincode,
      gstNumber: state.data.gstNumber,
      panNumber: state.data.panNumber,
      businessType: state.data.businessType,
      dealerType: state.data.dealerType,
      documents: state.data.documents,
      submittedDate: state.data.submittedDate,
      status: newStatus,
      rejectionReason: rejectionReason ?? state.data.rejectionReason,
    );

    state = state.copyWith(data: updatedData);
  }
}

final registrationProvider =
    StateNotifierProvider<RegistrationNotifier, RegistrationState>((ref) {
  return RegistrationNotifier();
});
