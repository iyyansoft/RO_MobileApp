class AddressModel {
  final String id;
  final String name;
  final String mobile;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;
  final String doorNo, street, area;

  const AddressModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    this.isDefault = false,
    this.doorNo = '',
    this.street = '',
    this.area = '',
  });

  AddressModel copyWith({
    String? id,
    String? name,
    String? mobile,
    String? address,
    String? city,
    String? state,
    String? pincode,
    bool? isDefault,
  }) {
    return AddressModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      isDefault: isDefault ?? this.isDefault,
      doorNo: address == null ? doorNo : '',
      street: address ?? street,
      area: address == null ? area : '',
    );
  }
}
