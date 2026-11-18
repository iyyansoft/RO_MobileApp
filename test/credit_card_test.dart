import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/profile/presentation/widgets/profile_sections.dart';

void main() {
  testWidgets('no credit limit configured: says so, shows outstanding, no fake figures', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CreditCard(availableCredit: null, outstanding: 2275),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('credit-not-set')), findsOneWidget);
    expect(find.textContaining('2,275'), findsOneWidget);
    expect(find.textContaining('2,50,000'), findsNothing);
    expect(find.byKey(const ValueKey('credit-progress')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configured limit: available, used and progress from the backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CreditCard(
              availableCredit: 97725,
              creditLimit: 100000,
              outstanding: 2275,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('credit-available')), findsOneWidget);
    expect(find.byKey(const ValueKey('credit-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('credit-not-set')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
