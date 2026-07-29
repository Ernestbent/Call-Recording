import 'dart:math';

import 'package:calls_recording/screens/splash_screen.dart';
import 'package:calls_recording/screens/pattern_setup_screen.dart';
import 'package:calls_recording/services/app_lock_service.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first app opening requires pattern setup before the splash', (
    tester,
  ) async {
    final service = AppLockService(
      storage: _MemoryAppLockStorage(),
      secureRandom: Random(17),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppLockGate(
          appState: CustomerCallStore(),
          appLockService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PatternSetupScreen), findsOneWidget);
    expect(find.text('Create your unlock pattern'), findsOneWidget);
    expect(find.byKey(const Key('pattern-setup-grid')), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('configured app lock is shown before splash is constructed', (
    tester,
  ) async {
    final service = AppLockService(
      storage: _MemoryAppLockStorage(),
      secureRandom: Random(17),
    );
    await service.savePattern([0, 1, 4, 7]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppLockGate(
          appState: CustomerCallStore(),
          appLockService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock AutoZone'), findsOneWidget);
    expect(find.byKey(const Key('autozone-lock-logo')), findsOneWidget);
    expect(find.byKey(const Key('fingerprint-method-option')), findsOneWidget);
    expect(find.byKey(const Key('pattern-method-option')), findsOneWidget);
    expect(find.byKey(const Key('pattern-unlock-grid')), findsNothing);
    expect(find.byType(SplashScreen), findsNothing);

    await tester.tap(find.byKey(const Key('pattern-method-option')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pattern-unlock-grid')), findsOneWidget);
    expect(
      find.byKey(const Key('choose-unlock-method-button')),
      findsOneWidget,
    );
  });
}

class _MemoryAppLockStorage implements AppLockStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
