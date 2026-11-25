import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/category_price_view.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_share.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/share_text_cleaner.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_card.dart';

final _supplierWords = RegExp(
  r'distributor|supplier|price list|\(\s*\)|\s[.,;:]|\.\.',
  caseSensitive: false,
);

/// Real phrases from the live catalogue (descriptions, specs, features).
const corpus = [
  'Distributors describe the Aqua 2090 cabinet as a 10-litre storage cabinet with a food-grade ABS body.',
  '10 litres (distributors)',
  'Food-grade ABS (distributor)',
  'Part of the Aqua Roma series (cherry, grey) offered by the supplier.',
  'The supplier lists this model as ABS plastic.',
  'The supplier lists a 1-year warranty.',
  'The exact mineral composition of this cartridge is not stated by the supplier.',
  "Nexus 'Turbo 300 GPD' booster pump (named 'Nixus' in the supplier price list) for light-commercial RO systems.",
  'C and X type clamps for RO purifiers: plastic holder clips (the supplier photo shows a three-slot clip) used to hold filter cartridges.',
  'The supplier photo shows the KW9 micro-switch type used in these switches.',
  '100 LPH commercial RO machine, shown in the supplier photo as a stainless frame with three blue jumbo housings and booster pumps.',
  'It is rated by name at 100 litres per hour of purified water and is listed by the supplier among commercial RO plants.',
  'it is the D-type mounting style of the two float types in the supplier range.',
  'Supplier catalogue model for domestic RO assembly',
  "Commercial RO plant from the supplier's range",
  '1 year (supplier price list)',
  '300 GPD RO membrane for light-commercial RO systems, supplied sealed in a pouch (supplier photo).',
];

ProductModel _p(String sku, String category, Map<String, Object?> extra) =>
    ProductModel.fromJson({
      'id': 'PDF_$sku',
      'sku': sku,
      'name': 'Product $sku',
      'category_key': category,
      'category_name': category,
      'price': 100,
      'mrp': 200,
      ...extra,
    });

void main() {
  test('the app and the share page use the same rules (share_text_rules.json)', () {
    final json =
        jsonDecode(File('share_text_rules.json').readAsStringSync()) as Map;
    final rules = [
      for (final r in json['rules'] as List) ((r as List)[0] as String, r[1] as String),
    ];
    expect(rules, shareTextRules);
    expect(json['leftover'], shareTextLeftover);
  });

  test('the three requested examples', () {
    expect(cleanShareItem('10 litres (distributors)'), '10 litres');
    expect(cleanShareItem('Food-grade ABS (distributor)'), 'Food-grade ABS');
    expect(
      cleanShareText(
        'Distributors describe the Aqua 2090 cabinet as a 10-litre storage cabinet with a food-grade ABS body.',
      ),
      'The Aqua 2090 cabinet is a 10-litre storage cabinet with a food-grade ABS body.',
    );
  });

  test('every real phrase is cleaned; no leftover words, brackets or punctuation', () {
    for (final phrase in corpus) {
      for (final out in [cleanShareText(phrase), cleanShareItem(phrase)]) {
        expect(out, isNot(matches(_supplierWords)), reason: phrase);
        expect(out, isNotEmpty, reason: phrase);
      }
    }
    // Legitimate information is kept.
    expect(cleanShareText(corpus[6]),
        'The exact mineral composition of this cartridge is not stated.');
    expect(cleanShareText(corpus[5]), 'It comes with a 1-year warranty.');
    expect(cleanShareText(corpus.last),
        '300 GPD RO membrane for light-commercial RO systems, supplied sealed in a pouch.');
    expect(cleanShareItem('Supplied in a sealed pouch'), 'Supplied in a sealed pouch');
    expect(cleanShareItem('Carbon block'), 'Carbon block', reason: 'unchanged');
  });

  test('share outputs for Cabinet, RO Systems, Membranes, Filters, Booster Pumps', () {
    final products = [
      _p('CAB-17', 'Cabinet', {
        'description':
            'Aqua 2090 RO purifier cabinet in black (203). Distributors describe the Aqua 2090 cabinet as a 10-litre storage cabinet with a food-grade ABS body.',
        'specs': {'Model': 'Aqua 2090', 'Colour': 'Black (203)', 'Storage': '10 litres (distributors)', 'Body material': 'Food-grade ABS (distributor)'},
        'features': ['10-litre storage (distributors)', 'Food-grade ABS body (distributor)', 'Houses filters, membrane, pump and wiring'],
        'cabinet_price': 1850,
      }),
      _p('MUK-24', 'RO Systems', {
        'description':
            '25 LPH commercial RO machine, shown in the supplier photo as a frame-mounted unit. It is listed by the supplier among commercial RO plants.',
        'features': ["Commercial RO plant from the supplier's range"],
      }),
      _p('MUK-23', 'Membranes', {
        'description': '300 GPD RO membrane, supplied sealed in a pouch (supplier photo).',
        'features': ['Sealed packaging (supplier photo)'],
      }),
      _p('DOM-05', 'Filters & Cartridges', {
        'description':
            '4-inch mineral cartridge (supplier photo). The exact mineral composition of this cartridge is not stated by the supplier.',
        'specs': {'Body': 'Transparent (supplier photo)'},
      }),
      _p('MUK-02', 'Booster Pumps', {
        'description': 'Maxx Flow 100 GPD booster pump. The supplier lists a 1-year warranty.',
        'specs': {'Warranty': '1 year (supplier price list)'},
        'features': ['1-year warranty (supplier)'],
      }),
    ];
    for (final p in products) {
      for (final view in ProductPriceView.values) {
        for (final out in [
          whatsAppShareText(p, view: view),
          productShareText(p, view: view),
          whatsAppShareUri(p, view: view).queryParameters['text']!,
          shareCardText(p, view: view).join('\n'),
        ]) {
          expect(out, isNot(matches(_supplierWords)), reason: '${p.sku} $view');
        }
      }
    }
    final cab = whatsAppShareText(products[0]);
    expect(cab, contains('The Aqua 2090 cabinet is a 10-litre storage cabinet'));
    expect(cab, contains('Storage: 10 litres\n'));
    expect(cab, contains('Body material: Food-grade ABS'));
    expect(cab, contains('Colour: Black (203)'), reason: 'other brackets kept');
    expect(cab, contains('- 10-litre storage\n'));
    expect(cab, contains('Contact us for orders and enquiries.'));
    expect(whatsAppShareText(products[4]), contains('Warranty: 1 year'));
    expect(whatsAppShareText(products[4]), contains('- 1-year warranty'));
    // The saved product is not changed.
    expect(products[0].description, contains('Distributors describe'));
    expect(products[0].specifications['Storage'], '10 litres (distributors)');
  });

  test('Node (share page) and Dart clean the real phrases identically', () async {
    const script = '''
const { cleanShareText, cleanShareItem } = require('./share_text.js');
const corpus = JSON.parse(process.argv[1]);
console.log(JSON.stringify(corpus.map(t => [cleanShareText(t), cleanShareItem(t)])));
''';
    final ProcessResult result;
    try {
      result = await Process.run('node', ['-e', script, jsonEncode(corpus)]);
    } on ProcessException {
      markTestSkipped('node is not installed');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final node = (jsonDecode(result.stdout as String) as List)
        .map((e) => [(e as List)[0], e[1]])
        .toList();
    final dart = [for (final t in corpus) [cleanShareText(t), cleanShareItem(t)]];
    expect(dart, node);
  });
}
