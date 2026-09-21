class UserModel {
  final String id;
  final String name;
  final String phoneNumber;
  final String companyName;
  final String gstNumber;
  final bool isGstVerified;

  const UserModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.companyName,
    required this.gstNumber,
    this.isGstVerified = true,
  });

  static const UserModel demoDealer = UserModel(
    id: 'dlr_101',
    name: 'Rajesh Kumar',
    phoneNumber: '+91 98765 43210',
    companyName: 'Aqua Tech Solutions',
    gstNumber: '27AABCU9603R1ZM',
    isGstVerified: true,
  );
}
