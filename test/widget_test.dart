// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:calls_recording/main.dart';
import 'package:calls_recording/services/customer_call_store.dart';

void main() {
  testWidgets('home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(appState: CustomerCallStore()));

    expect(find.text('Call Recorder'), findsOneWidget);
    expect(find.text('Every conversation, organised.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();

    expect(find.text('RECORDINGS READY'), findsOneWidget);
  });
}
