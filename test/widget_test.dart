import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/screens/splash_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:calls_recording/services/secure_session_storage.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('splash opens login when there is no saved session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SplashScreen(
          appState: _testCustomerCallStore(),
          erpNextAuthenticator: _SuccessfulErpNextAuthenticator(),
          sessionStorage: _MemorySessionStorage(),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Call Recorder'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('RECORDINGS READY'), findsNothing);
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
  });

  testWidgets('splash bypasses login for a valid saved ERPNext session', (
    WidgetTester tester,
  ) async {
    final sessionStorage = _MemorySessionStorage()..session = _testSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SplashScreen(
          appState: _testCustomerCallStore(),
          erpNextAuthenticator: _SuccessfulErpNextAuthenticator(),
          sessionStorage: sessionStorage,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();

    expect(find.text('RECORDINGS READY'), findsOneWidget);
    expect(find.text('Welcome Back'), findsNothing);
  });

  testWidgets('splash clears an expired ERPNext session and opens login', (
    WidgetTester tester,
  ) async {
    final sessionStorage = _MemorySessionStorage()..session = _testSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SplashScreen(
          appState: _testCustomerCallStore(),
          erpNextAuthenticator: _ExpiredErpNextAuthenticator(),
          sessionStorage: sessionStorage,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(sessionStorage.session, isNull);
  });

  testWidgets('ERPNext login saves its session and opens home', (
    WidgetTester tester,
  ) async {
    final sessionStorage = _MemorySessionStorage();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(
          appState: _testCustomerCallStore(),
          erpNextAuthenticator: _SuccessfulErpNextAuthenticator(),
          sessionStorage: sessionStorage,
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

class _ExpiredErpNextAuthenticator extends _SuccessfulErpNextAuthenticator {
  @override
  Future<bool> isSessionValid(ErpNextSession session) async => false;
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

class _EmptyDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    return const [];
  }
}

CustomerCallStore _testCustomerCallStore() {
  return CustomerCallStore(customerSource: _EmptyDraftPaymentCustomerSource());
}

ErpNextSession _testSession() {
  return ErpNextSession(
    sessionId: 'saved-test-session',
    userId: 'agent@example.com',
    fullName: 'Test Agent',
    createdAt: DateTime.utc(2026, 7, 24),
  );
}
