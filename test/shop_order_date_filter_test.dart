import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

/// Records every GET shop/orders request; the server does the date filtering
/// (tested in test/shop_order_sync_postgres_test.cjs), so this checks what the
/// Shop App asks for.
class _Recorder {
  final queries = <Map<String, dynamic>>[];

  ShopEmployeeRepository repo() {
    final dio = Dio(BaseOptions(baseUrl: 'http://shop.test/api/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('shop/orders')) {
            queries.add(Map<String, dynamic>.from(options.queryParameters));
          }
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'success': true, 'orders': <Map<String, dynamic>>[]},
            ),
          );
        },
      ),
    );
    return ShopEmployeeRepository.forTesting(dio);
  }
}

/// Today in Asia/Kolkata, the same rule the Shop App uses.
DateTime _istToday() {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(ist.year, ist.month, ist.day);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _pump(WidgetTester tester, _Recorder recorder) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShopOrdersScreen(
          repo: recorder.repo(),
          active: true,
          refreshInterval: const Duration(minutes: 5),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choosePreset(WidgetTester tester, String preset) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(preset).last);
  await tester.pumpAndSettle();
}

/// Picks [day] in the calendar that is open (the dialog's own day buttons).
Future<void> _pickDayInCalendar(WidgetTester tester, int day) async {
  await tester.tap(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text('$day'),
    ).first,
  );
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Last 7 Days is the default and asks for the Kolkata date range', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    final today = _istToday();
    expect(recorder.queries.last['from'], _iso(today.subtract(const Duration(days: 6))));
    expect(recorder.queries.last['to'], _iso(today));
    expect(find.text('Order date'), findsOneWidget);
  });

  testWidgets('Today, Yesterday, Last 30 Days, This Month and Last Month send exact inclusive ranges', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    final today = _istToday();
    final cases = <String, (DateTime, DateTime)>{
      'Today': (today, today),
      'Yesterday': (
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      'Last 30 Days': (today.subtract(const Duration(days: 29)), today),
      'This Month': (DateTime(today.year, today.month), today),
      'Last Month': (
        DateTime(today.year, today.month - 1),
        DateTime(today.year, today.month, 0),
      ),
    };
    for (final entry in cases.entries) {
      await _choosePreset(tester, entry.key);
      expect(
        recorder.queries.last,
        containsPair('from', _iso(entry.value.$1)),
        reason: '${entry.key} from',
      );
      expect(
        recorder.queries.last,
        containsPair('to', _iso(entry.value.$2)),
        reason: '${entry.key} to',
      );
    }
  });

  testWidgets('Custom Date shows From and To calendar fields (no typing)', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    await _choosePreset(tester, 'Custom Date');
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(1), reason: 'only the search box is typeable');
    expect(find.text('Apply Filter'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Custom Date Selection'), findsOneWidget);
    // Empty until the user picks dates, as in the reference.
    expect(find.text('DD/MM/YYYY'), findsNWidgets(2));
    expect(find.byIcon(Icons.calendar_month_outlined), findsNWidgets(3), reason: 'dropdown + two fields');
  });

  testWidgets('opening Custom Date sends nothing: the list changes only on Apply Filter', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    final before = recorder.queries.length;
    await _choosePreset(tester, 'Custom Date');
    expect(recorder.queries.length, before);
    expect(find.text('Custom Date Selection'), findsOneWidget);
  });

  testWidgets('a From Date later than the To Date is refused and nothing is requested', (
    tester,
  ) async {
    final today = _istToday();
    if (today.day < 2) {
      markTestSkipped('needs a day of the month after the 1st to pick an earlier To Date');
      return;
    }
    final recorder = _Recorder();
    await _pump(tester, recorder);
    await _choosePreset(tester, 'Custom Date');
    final before = recorder.queries.length;

    // From = today, then To = the 1st of this month: To is earlier than From.
    await tester.tap(find.byKey(const ValueKey('date-field-From Date')));
    await tester.pumpAndSettle();
    await _pickDayInCalendar(tester, today.day);
    await tester.tap(find.byKey(const ValueKey('date-field-To Date')));
    await tester.pumpAndSettle();
    await _pickDayInCalendar(tester, 1);

    expect(find.text('To Date cannot be earlier than From Date.'), findsOneWidget);
    await tester.tap(find.text('Apply Filter'));
    await tester.pumpAndSettle();
    expect(recorder.queries.length, before, reason: 'an invalid range is not sent');
    expect(find.text('To Date cannot be earlier than From Date.'), findsOneWidget);
  });

  testWidgets('a valid From/To range is applied inclusively when Apply Filter is pressed', (
    tester,
  ) async {
    final today = _istToday();
    final recorder = _Recorder();
    await _pump(tester, recorder);
    await _choosePreset(tester, 'Custom Date');

    // From = the 1st of this month, To = today (the picker stops at today).
    await tester.tap(find.byKey(const ValueKey('date-field-From Date')));
    await tester.pumpAndSettle();
    await _pickDayInCalendar(tester, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('date-field-From Date')),
        matching: find.text(_shortDate(DateTime(today.year, today.month, 1))),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('date-field-To Date')));
    await tester.pumpAndSettle();
    await _pickDayInCalendar(tester, today.day);

    await tester.tap(find.text('Apply Filter'));
    await tester.pumpAndSettle();
    expect(recorder.queries.last['from'], _iso(DateTime(today.year, today.month, 1)));
    expect(recorder.queries.last['to'], _iso(today));
    expect(find.text('To Date cannot be earlier than From Date.'), findsNothing);
  });

  testWidgets('Clear restores Last 7 Days and the default list', (tester) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    await _choosePreset(tester, 'This Month');
    await _choosePreset(tester, 'Custom Date');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    final today = _istToday();
    expect(recorder.queries.last['from'], _iso(today.subtract(const Duration(days: 6))));
    expect(recorder.queries.last['to'], _iso(today));
    expect(find.text('From Date'), findsNothing, reason: 'panel closed');
  });

  for (final size in const [Size(390, 844), Size(800, 1000), Size(1280, 900)]) {
    testWidgets('custom date panel lays out without overflow at ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopOrdersScreen(
              repo: _Recorder().repo(),
              active: true,
              refreshInterval: const Duration(minutes: 5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _choosePreset(tester, 'Custom Date');
      expect(find.text('Apply Filter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the date filter is sent together with search and status', (tester) async {
    final recorder = _Recorder();
    await _pump(tester, recorder);
    await _choosePreset(tester, 'Last 30 Days');
    await tester.enterText(find.byType(TextField).first, 'Priya');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pending'));
    await tester.pumpAndSettle();
    final today = _istToday();
    final last = recorder.queries.last;
    expect(last['search'], 'Priya');
    expect(last['status'], 'pending');
    expect(last['from'], _iso(today.subtract(const Duration(days: 29))));
    expect(last['to'], _iso(today));
  });
}

/// How the calendar and fields show a date, e.g. "3 Nov 2026".
String _shortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
