enum ApprovalStatus {
  pending,
  approved,
  rejected;

  String get label {
    switch (this) {
      case ApprovalStatus.pending:
        return 'Pending Verification';
      case ApprovalStatus.approved:
        return 'Account Approved';
      case ApprovalStatus.rejected:
        return 'Application Rejected';
    }
  }
}

class UploadedDoc {
  final String docType;
  final String fileName;
  final double uploadProgress;
  final bool isUploaded;

  const UploadedDoc({
    required this.docType,
    required this.fileName,
    this.uploadProgress = 1.0,
    this.isUploaded = true,
  });
}

class DealerRegistrationModel {
  final String applicationId;
  final String businessName;
  final String ownerName;
  final String mobile;
  final String email;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String gstNumber;
  final String panNumber;
  final String businessType;
  final String dealerType;
  final List<UploadedDoc> documents;
  final ApprovalStatus status;
  final String submittedDate;
  final String? rejectionReason;

  const DealerRegistrationModel({
    required this.applicationId,
    required this.businessName,
    required this.ownerName,
    required this.mobile,
    required this.email,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.gstNumber,
    required this.panNumber,
    required this.businessType,
    required this.dealerType,
    required this.documents,
    this.status = ApprovalStatus.pending,
    required this.submittedDate,
    this.rejectionReason,
  });

  static const DealerRegistrationModel empty = DealerRegistrationModel(
    applicationId: '',
    businessName: '',
    ownerName: '',
    mobile: '',
    email: '',
    address: '',
    city: '',
    state: '',
    pincode: '',
    gstNumber: '',
    panNumber: '',
    businessType: '',
    dealerType: '',
    submittedDate: '',
    documents: [],
  );
}
