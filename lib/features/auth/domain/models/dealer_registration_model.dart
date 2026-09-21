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

  static DealerRegistrationModel defaultMock = DealerRegistrationModel(
    applicationId: 'APP-2026-98421',
    businessName: 'Aqua Tech Water Solutions',
    ownerName: 'Rajesh Kumar',
    mobile: '+91 98765 43210',
    email: 'rajesh@aquatech.com',
    address: 'Plot 42, Industrial Area Phase 2',
    city: 'Mumbai',
    state: 'Maharashtra',
    pincode: '400072',
    gstNumber: '27AABCU9603R1ZM',
    panNumber: 'ABCDE1234F',
    businessType: 'Proprietorship',
    dealerType: 'Wholesale Dealer',
    submittedDate: '03 Sep 2026, 11:23 AM',
    status: ApprovalStatus.pending,
    rejectionReason: 'GST certificate document scan is blurry. Please upload a clear original PDF copy.',
    documents: const [
      UploadedDoc(docType: 'GST Certificate', fileName: 'gst_certificate_2026.pdf'),
      UploadedDoc(docType: 'PAN Card', fileName: 'pan_card_front.jpg'),
      UploadedDoc(docType: 'Business Proof', fileName: 'shop_license.pdf'),
      UploadedDoc(docType: 'Address Proof', fileName: 'electricity_bill.pdf'),
    ],
  );
}
