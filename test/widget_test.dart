import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calls_recording/main.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/services/biometric_auth_service.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:calls_recording/services/secure_session_storage.dart';
import 'package:calls_recording/theme/app_theme.dart';

void main() {
  testWidgets('splash opens login before the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(appState: CustomerCallStore()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Call Recorder'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('RECORDINGS READY'), findsNothing);
    expect(find.byKey(const Key('fingerprint-login-button')), findsOneWidget);
  });

  testWidgets('ERPNext login saves its session and opens home', (
    WidgetTester tester,
  ) async {
    final sessionStorage = _MemorySessionStorage();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(
          appState: CustomerCallStore(),
          erpNextAuthenticator: _SuccessfulErpNextAuthenticator(),
          sessionStorage: sessionStorage,
          biometricAuthenticator: _SuccessfulBiometricAuthenticator(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'agent@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'password',
    );
    await tester.ensureVisible(find.byKey(const Key('login-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pumpAndSettle();

    expect(find.text('RECORDINGS READY'), findsOneWidget);
    expect(sessionStorage.session?.userId, 'agent@example.com');
  });

  testWidgets('fingerprint remains independent from ERPNext login', (
    WidgetTester tester,
  ) async {
    final erpNextAuthenticator = _SuccessfulErpNextAuthenticator();
    final sessionStorage = _MemorySessionStorage();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(
          appState: CustomerCallStore(),
          erpNextAuthenticator: erpNextAuthenticator,
          sessionStorage: sessionStorage,
          biometricAuthenticator: _SuccessfulBiometricAuthenticator(),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('fingerprint-login-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fingerprint-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('RECORDINGS READY'), findsOneWidget);
    expect(erpNextAuthenticator.loginCalls, 0);
    expect(sessionStorage.session, isNull);
  });
}

class _SuccessfulErpNextAuthenticator implements ErpNextAuthenticator {
  int loginCalls = 0;

  @override
  Future<ErpNextSession> login({
    required String username,
    required String password,
  }) async {
    loginCalls++;
    return ErpNextSession(
      sessionId: 'test-session',
      userId: username,
      fullName: 'Test Agent',
      createdAt: DateTime.utc(2026, 7, 24),
    );
  }

  @override
  Future<bool> isSessionValid(ErpNextSession session) async => true;

  @override
  Future<void> logout(ErpNextSession session) async {}
}

class _MemorySessionStorage implements SessionStorage {
  ErpNextSession? session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<ErpNextSession?> read() async => session;

  @override
  Future<void> save(ErpNextSession session) async {
    this.session = session;
  }
}

class _SuccessfulBiometricAuthenticator implements BiometricAuthenticator {
  @override
  Future<bool> authenticate() async => true;
}
