import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_files.dart';

Uint8List _productWorkbook(List<String> headers) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  sheet.appendRow([
    TextCellValue(''),
    TextCellValue('RO Membrane 100 GPD'),
    TextCellValue('MEM-100'),
    TextCellValue('membranes'),
    TextCellValue('Aqua'),
    const IntCellValue(500),
    const IntCellValue(900),
    const IntCellValue(1200),
    const IntCellValue(1),
    const IntCellValue(20),
    TextCellValue('High-flow replacement membrane'),
  ]);
  return Uint8List.fromList(workbook.encode()!);
}

void main() {
  test('the bulk template exposes product name and description columns', () {
    expect(AdminFiles.productHeaders, contains('Product Name'));
    expect(AdminFiles.productHeaders, contains('Product Description'));
  });

  test(
    'Excel parser reads new headers and keeps legacy headers compatible',
    () {
      for (final headers in [
        AdminFiles.productHeaders,
        [
          'Image',
          'Name',
          'SKU',
          'Category',
          'Brand',
          'Purchase Price',
          'Dealer Price',
          'MRP',
          'MOQ',
          'Stock',
          'Description',
        ],
      ]) {
        final products = AdminFiles.parseProductsWorkbook(
          _productWorkbook(headers),
        );
        expect(products, hasLength(1));
        expect(products.single['name'], 'RO Membrane 100 GPD');
        expect(products.single['sku'], 'MEM-100');
        expect(products.single['desc'], 'High-flow replacement membrane');
        expect(products.single['price'], 900);
      }
    },
  );
}
