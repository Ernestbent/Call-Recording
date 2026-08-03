import 'package:calls_recording/main.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app switches theme mode and persists the preference', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final appState = CustomerCallStore();
    await appState.hydrate();

    await tester.pumpWidget(MyApp(appState: appState));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await appState.setDarkMode(true);
    await tester.pump();

    expect(appState.isDarkMode, isTrue);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    final restoredState = CustomerCallStore();
    await restoredState.hydrate();
    expect(restoredState.isDarkMode, isTrue);
  });
}
