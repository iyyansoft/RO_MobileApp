import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class AdminFiles {
  static const productHeaders = [
    'Image',
    'Product Name',
    'SKU Code',
    'Category',
    'Brand',
    'Purchase Price',
    'Dealer Price',
    'MRP',
    'MOQ',
    'Stock',
    'Product Description',
  ];
  static const productExample = {
    'Image': 'https://example.com/product.jpg',
    'Product Name': 'RO Membrane',
    'SKU Code': 'MEM-001',
    'Category': 'membranes',
    'Brand': 'Aqua',
    'Purchase Price': 400,
    'Dealer Price': 500,
    'MRP': 650,
    'MOQ': 1,
    'Stock': 50,
    'Product Description': 'High performance RO membrane',
  };

  static Future<String?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > 5 * 1024 * 1024) {
      throw Exception('Image must be smaller than 5 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('Image must be smaller than 5 MB.');
    }
    final extension = file.extension?.toLowerCase();
    final mime = extension == 'jpg' || extension == 'jpeg' ? 'jpeg' : extension;
    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  }

  static Future<bool> exportRows(
    String name,
    List<Map<String, dynamic>> rows, {
    List<String>? headers,
  }) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Records'];
    workbook.setDefaultSheet('Records');
    workbook.delete('Sheet1');
    final columns = headers ?? rows.expand((row) => row.keys).toSet().toList();
    sheet.appendRow(columns.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(
        columns.map((key) {
          final value = row[key];
          if (value is int) return IntCellValue(value);
          if (value is double) return DoubleCellValue(value);
          if (value is bool) return BoolCellValue(value);
          return TextCellValue(
            value is Map || value is List
                ? jsonEncode(value)
                : '${value ?? ''}',
          );
        }).toList(),
      );
    }
    final bytes = Uint8List.fromList(workbook.encode()!);
    final destination = await FilePicker.saveFile(
      dialogTitle: 'Save Excel workbook',
      fileName: '$name.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: bytes,
    );
    return destination != null;
  }

  static dynamic _value(CellValue? cell) => switch (cell) {
    IntCellValue() => cell.value,
    DoubleCellValue() => cell.value,
    TextCellValue() => cell.value.toString(),
    BoolCellValue() => cell.value,
    _ => cell?.toString() ?? '',
  };

  static Future<List<Map<String, dynamic>>?> importProducts() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return parseProductsWorkbook(bytes);
  }

  static List<Map<String, dynamic>> parseProductsWorkbook(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw Exception('Workbook contains no worksheets.');
    }
    final rows = workbook.tables.values.first.rows;
    if (rows.length < 2) throw Exception('Workbook contains no product rows.');
    final headers = rows.first
        .map(
          (cell) => '${_value(cell?.value)}'.trim().toLowerCase().replaceAll(
            RegExp('[^a-z0-9]'),
            '',
          ),
        )
        .toList();
    final products = <Map<String, dynamic>>[];
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.every((cell) => '${_value(cell?.value)}'.trim().isEmpty)) {
        continue;
      }
      final values = <String, dynamic>{
        for (var col = 0; col < headers.length; col++)
          headers[col]: col < row.length ? _value(row[col]?.value) : '',
      };
      dynamic read(List<String> aliases, [dynamic fallback = '']) {
        for (final key in aliases) {
          if (values[key] != null && '${values[key]}'.trim().isNotEmpty) {
            return values[key];
          }
        }
        return fallback;
      }

      final name = read(['productdetails', 'productname', 'name']);
      final sku = read(['skucode', 'sku']);
      final category = read(['category', 'categorykey']);
      final price = num.tryParse('${read(['dealerprice', 'price'], 0)}');
      final purchase = num.tryParse('${read(['purchaseprice'], 0)}');
      final mrp = num.tryParse('${read(['mrp'], price ?? 0)}');
      final stock = int.tryParse('${read(['stockquantity', 'stock'], 50)}');
      final moq = '${read(['moq'], 1)}';
      final moqNumber = int.tryParse(
        RegExp(r'\d+').firstMatch(moq)?.group(0) ?? '',
      );
      if ('$name'.trim().isEmpty ||
          '$sku'.trim().isEmpty ||
          '$category'.trim().isEmpty ||
          price == null ||
          price < 0 ||
          purchase == null ||
          purchase < 0 ||
          mrp == null ||
          mrp < 0 ||
          stock == null ||
          stock < 0 ||
          moqNumber == null ||
          moqNumber < 1 ||
          moq.trim().startsWith('-')) {
        throw Exception(
          'Row ${index + 1}: name, SKU, category, nonnegative prices/stock and MOQ of at least 1 are required.',
        );
      }
      dynamic jsonField(String key, dynamic fallback) {
        final value = read([key]);
        if ('$value'.trim().isEmpty) return fallback;
        try {
          return jsonDecode('$value');
        } catch (_) {
          throw Exception('Row ${index + 1}: $key must contain valid JSON.');
        }
      }

      products.add({
        'name': name,
        'sku': sku,
        'category': category,
        'brand': read(['brand']),
        'purchase_price': purchase,
        'price': price,
        'dealer_price': price,
        'mrp': mrp,
        'moq': moq,
        'stock_quantity': stock,
        'min_stock': int.tryParse('${read(['minstock'], 10)}') ?? 10,
        'img': read(['image', 'img', 'imageurl', 'imgurl']),
        'desc': read(['productdescription', 'desc', 'description']),
        'badge': read(['badge']),
        'specs': jsonField('specs', <String, dynamic>{}),
        'features': jsonField('features', <String>[]),
        'status': read(['status'], 'active'),
      });
    }
    if (products.isEmpty) {
      throw Exception('Workbook contains no product records.');
    }
    return products;
  }
}
