import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

void main() {
  group(
    'Current Orders preview screen',
    skip: const bool.fromEnvironment('SHOP_ORDERS_PREVIEW')
        ? false
        : 'Requires --dart-define=SHOP_ORDERS_PREVIEW=true',
    () {
      Future<void> mount(WidgetTester tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShopOrdersScreen(
                repo: ShopEmployeeRepository.instance,
                onNewEnquiry: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets(
        'existing Current Orders screen shows clearly labeled sample orders',
        (tester) async {
          await mount(tester);

          expect(find.text('Priya Enterprises'), findsNWidgets(2));
          expect(find.text('SB Distributors'), findsNWidgets(2));
          expect(find.textContaining('SAMPLE-RO-2401'), findsOneWidget);
          expect(find.textContaining('SAMPLE-RO-2402'), findsOneWidget);
          expect(find.text('Supply'), findsAtLeastNWidgets(1));
          expect(find.text('New Enquiry'), findsOneWidget);
          expect(find.text('Dealer Price'), findsAtLeastNWidgets(1));
        },
      );

      testWidgets('status chips filter the preview records', (tester) async {
        await mount(tester);
        await tester.tap(
          find.widgetWithText(ChoiceChip, 'Partially Delivered'),
        );
        await tester.pumpAndSettle();

        expect(find.text('SB Distributors'), findsNWidgets(2));
        expect(find.text('Priya Enterprises'), findsNothing);
        expect(find.textContaining('SAMPLE-RO-2402'), findsOneWidget);
        expect(find.text('Supply'), findsOneWidget);
      });

      testWidgets('search filters by product name in the existing screen', (
        tester,
      ) async {
        await mount(tester);
        await tester.enterText(find.byType(TextField).first, 'UV Lamp 11W');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Neeraj Water Solutions'), findsNWidgets(2));
        expect(find.textContaining('SAMPLE-RO-2404'), findsOneWidget);
        expect(find.text('Priya Enterprises'), findsNothing);
      });
    },
  );
}
