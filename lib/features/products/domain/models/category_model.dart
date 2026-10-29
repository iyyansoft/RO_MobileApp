import 'product_model.dart';

class CategoryModel {
  final String id;
  final String name;
  final String imagePath;
  final int productCount;
  final String description;
  final String? databaseId;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.productCount,
    required this.description,
    this.databaseId,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
    id: [json['key_name'], json['key'], json['id']]
        .map((value) => '${value ?? ''}'.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
    databaseId: json['id']?.toString().trim(),
    name: '${json['title'] ?? json['name'] ?? ''}',
    imagePath: '${json['image_url'] ?? json['image'] ?? ''}',
    productCount: int.tryParse('${json['product_count'] ?? 0}') ?? 0,
    description: '${json['description'] ?? ''}',
  );

  bool matchesProduct(ProductModel product) {
    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final identities = [
      id,
      databaseId ?? '',
      name,
    ].map(normalize).where((value) => value.isNotEmpty).toSet();
    return identities.contains(normalize(product.categoryId)) ||
        identities.contains(normalize(product.categoryName));
  }

  CategoryModel withProductCount(int count) => CategoryModel(
    id: id,
    databaseId: databaseId,
    name: name,
    imagePath: imagePath,
    productCount: count,
    description: description,
  );
}
