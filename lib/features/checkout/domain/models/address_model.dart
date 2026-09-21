class AddressModel {
  final String id;
  final String name;
  final String mobile;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;

  const AddressModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    this.isDefault = false,
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
    );
  }

  static const List<AddressModel> sampleAddresses = [
    AddressModel(
      id: 'addr_1',
      name: 'Rajesh Kumar (Aqua Tech Solutions)',
      mobile: '+91 98765 43210',
      address: 'Plot 42, Industrial Area Phase 2, Near Water Plant',
      city: 'Mumbai',
      state: 'Maharashtra',
      pincode: '400072',
      isDefault: true,
    ),
    AddressModel(
      id: 'addr_2',
      name: 'Aqua Tech Warehouse Depot',
      mobile: '+91 98200 11223',
      address: 'Shed 12, Logistics Park, Bhiwandi Road',
      city: 'Thane',
      state: 'Maharashtra',
      pincode: '421302',
      isDefault: false,
    ),
  ];
}
