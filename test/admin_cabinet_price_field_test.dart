import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/presentation/widgets/admin_product_fields.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';

const categories = [
  CategoryModel(id: 'filters', name: 'Filters & Cartridges', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'cabinets', name: 'Cabinet', imagePath: '', productCount: 0, description: ''),
];

Map<String, TextEditingController> controllersFor(String category, {String cabinetPrice = ''}) => {
  for (final key in ['name', 'sku', 'category', 'brand', 'img', 'purchase_price', 'price', 'mrp', 'cabinet_price', 'moq', 'stock_quantity', 'desc'])
    key: TextEditingController(),
}
  ..['category']!.text = category
  ..['cabinet_price']!.text = cabinetPrice
  ..['stock_quantity']!.text = '0';

Future<GlobalKey<FormState>> pump(WidgetTester tester, Map<String, TextEditingController> c) async {
  final form = GlobalKey<FormState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Form(key: form, child: AdminProductFields(controllers: c, categories: categories, showAdvanced: false)),
      ),
    ),
  ));
  return form;
}

final cabinetField = find.byKey(const ValueKey('cabinet_price'));

void main() {
  testWidgets('Cabinet Price appears only for the Cabinet category', (tester) async {
    final c = controllersFor('filters');
    await pump(tester, c);
    expect(cabinetField, findsNothing);
    expect(find.text('Cabinet Price (₹) *'), findsNothing);

    c['category']!.text = 'cabinets';
    await tester.pump();
    expect(cabinetField, findsOneWidget);
    expect(find.text('Cabinet Price (₹) *'), findsOneWidget);

    c['category']!.text = 'filters';
    await tester.pump();
    expect(cabinetField, findsNothing);
  });

  testWidgets('required for Cabinet; not validated for other categories', (tester) async {
    final c = controllersFor('cabinets')
      ..['name']!.text = 'Cab'
      ..['sku']!.text = 'CAB-X';
    final form = await pump(tester, c);
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(cabinetField, '0');
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(cabinetField, '950');
    expect(form.currentState!.validate(), isTrue);

    final other = controllersFor('filters')
      ..['name']!.text = 'Valve'
      ..['sku']!.text = 'V-1';
    final otherForm = await pump(tester, other);
    expect(otherForm.currentState!.validate(), isTrue);
  });

  testWidgets('editing a Cabinet product shows its saved Cabinet Price', (tester) async {
    await pump(tester, controllersFor('cabinets', cabinetPrice: '1100'));
    expect(find.text('1100'), findsOneWidget);
  });

  test('recognises the Cabinet category', () {
    expect(AdminProductFields.isCabinetCategory('cabinets', categories), isTrue);
    expect(AdminProductFields.isCabinetCategory('CAT_CAB', categories), isTrue);
    expect(AdminProductFields.isCabinetCategory('filters', categories), isFalse);
    expect(AdminProductFields.isCabinetCategory('', categories), isFalse);
  });
}
