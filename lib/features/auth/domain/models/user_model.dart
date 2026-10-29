class UserModel {
  final String id,
      name,
      email,
      phoneNumber,
      companyName,
      address,
      gstNumber,
      status,
      token;
  final bool isGstVerified;
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.companyName,
    required this.address,
    required this.gstNumber,
    required this.status,
    required this.token,
    this.isGstVerified = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? json['owner'] ?? ''}',
    email: '${json['email'] ?? ''}',
    phoneNumber: '${json['mobile'] ?? ''}',
    companyName: '${json['business'] ?? json['businessName'] ?? ''}',
    address: '${json['address'] ?? ''}',
    gstNumber: '${json['gstNumber'] ?? json['gst_number'] ?? ''}',
    status: '${json['status'] ?? 'approved'}',
    token: '${json['token'] ?? ''}',
    isGstVerified: json['isApproved'] == true,
  );

  UserModel copyWith({
    String? name,
    String? phoneNumber,
    String? companyName,
    String? address,
    String? gstNumber,
  }) => UserModel(
    id: id,
    name: name ?? this.name,
    email: email,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    companyName: companyName ?? this.companyName,
    address: address ?? this.address,
    gstNumber: gstNumber ?? this.gstNumber,
    status: status,
    token: token,
    isGstVerified: isGstVerified,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'mobile': phoneNumber,
    'business': companyName,
    'address': address,
    'gstNumber': gstNumber,
    'status': status,
    'token': token,
    'isApproved': isGstVerified,
  };
}
