import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/models/api_credentials.dart';
import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/screens/customers_screen.dart';
import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/screens/settings.dart';
import 'package:calls_recording/screens/splash_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
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
          credentialManager: _MemoryAgentCredentialManager(),
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
          credentialManager: _MemoryAgentCredentialManager(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 3300));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('RECORDINGS READY').evaluate().isNotEmpty) break;
    }

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
          credentialManager: _MemoryAgentCredentialManager(),
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
          credentialManager: _MemoryAgentCredentialManager(),
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

  testWidgets('successful login opens home before customer sync finishes', (
    WidgetTester tester,
  ) async {
    final customerSource = _PendingDraftPaymentCustomerSource();
    final appState = CustomerCallStore(
      customerSource: customerSource,
      automaticDraftCustomerRefreshEnabled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(
          appState: appState,
          erpNextAuthenticator: _SuccessfulErpNextAuthenticator(),
          sessionStorage: _MemorySessionStorage(),
          credentialManager: _MemoryAgentCredentialManager(),
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
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('RECORDINGS READY').evaluate().isNotEmpty) break;
    }

    expect(find.text('RECORDINGS READY'), findsOneWidget);
    expect(appState.isLoadingCustomers, isTrue);

    customerSource.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Customers screen scrolls without overflow in landscape', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CustomersScreen(appState: _testCustomerCallStore()),
      ),
    );

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No customers with draft Payment Entries and a mobile number were found.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Customers summary and fetch action stay fixed while cards scroll',
    (WidgetTester tester) async {
      final appState = CustomerCallStore(
        customerSource: _EmptyDraftPaymentCustomerSource(),
        initialCustomers: List.generate(
          8,
          (index) => CustomerContact(
            name: 'Customer ${index + 1}',
            phoneNumber: '07000000$index',
            subtitle: '1 draft payment entry',
            statusLabel: '2 recordings ready; upload pending',
            matchingRecordingsCount: 2,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CustomersScreen(appState: appState),
        ),
      );
      await tester.pumpAndSettle();

      final summaryFinder = find.byKey(const Key('customers-summary-card'));
      final fetchFinder = find.byKey(const Key('fetch-all-recordings-button'));
      final summaryTop = tester.getTopLeft(summaryFinder).dy;
      final fetchTop = tester.getTopLeft(fetchFinder).dy;

      await tester.drag(
        find.byKey(const Key('customer-cards-scroll-view')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(summaryFinder).dy, summaryTop);
      expect(tester.getTopLeft(fetchFinder).dy, fetchTop);
      expect(find.text('Customer 1'), findsNothing);
      expect(find.text('Customer 8'), findsOneWidget);
    },
  );

  testWidgets(
    'customer call uses text button and photo opens in a large viewer',
    (WidgetTester tester) async {
      final appState = CustomerCallStore(
        customerSource: _EmptyDraftPaymentCustomerSource(),
        initialCustomers: [
          CustomerContact(
            name: 'Photo Customer',
            phoneNumber: '0700000099',
            profileImageUrl: 'https://example.com/customer.jpg',
            subtitle: '1 draft payment entry',
            statusLabel: 'Ready to call',
            latestPaymentEntryCreatedAt: DateTime(2026, 8, 3, 10, 30),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CustomersScreen(appState: appState),
        ),
      );

      final callButton = find.byKey(const Key('call-customer-0700000099'));
      final callButtonLabel = find.descendant(
        of: callButton,
        matching: find.text('Call'),
      );
      final callButtonImage = find.descendant(
        of: callButton,
        matching: find.byType(Image),
      );
      expect(callButton, findsOneWidget);
      expect(callButtonLabel, findsOneWidget);
      expect(callButtonImage, findsNothing);
      expect(
        find.text('Payment entry created 3 Aug 2026 at 10:30'),
        findsOneWidget,
      );
      expect(find.text('No call has been started from this app'), findsNothing);
      expect(find.text('2 recordings ready; upload pending'), findsNothing);
      expect(find.text('2 recordings ready to play'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('customer-avatar-0700000099')),
      );
      await tester.tap(find.byKey(const Key('customer-avatar-0700000099')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-image-viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Photo Customer'), findsWidgets);

      await tester.tap(find.byKey(const Key('close-customer-image-viewer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-image-viewer')), findsNothing);
    },
  );

  testWidgets('Settings profile shows the ERPNext user and logs out', (
    WidgetTester tester,
  ) async {
    final session = _testSession();
    final sessionStorage = _MemorySessionStorage()..session = session;
    final authenticator = _SuccessfulErpNextAuthenticator();
    final appState = _testCustomerCallStore();
    await appState.loadDraftPaymentCustomers(session);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsScreen(
          appState: appState,
          erpNextAuthenticator: authenticator,
          sessionStorage: sessionStorage,
          credentialManager: _MemoryAgentCredentialManager(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-dark-mode-switch')));
    await tester.pumpAndSettle();
    expect(appState.isDarkMode, isTrue);

    await tester.tap(find.byKey(const Key('settings-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('Test Agent'), findsOneWidget);
    expect(find.text('agent@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout-button')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(sessionStorage.session, isNull);
    expect(authenticator.logoutCalls, 1);
    expect(appState.customers, isEmpty);
  });
}

class _SuccessfulErpNextAuthenticator implements ErpNextAuthenticator {
  int loginCalls = 0;
  int logoutCalls = 0;

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
  Future<void> logout(ErpNextSession session) async {
    logoutCalls++;
  }
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

class _MemoryAgentCredentialManager implements AgentCredentialManager {
  ApiCredentials? credentials;

  @override
  Future<ApiCredentials> activateForEmail(String email) async {
    credentials = ApiCredentials(
      email: email,
      apiKey: 'test-api-key',
      apiSecret: 'test-api-secret',
    );
    return credentials!;
  }

  @override
  Future<void> clear() async {
    credentials = null;
  }

  @override
  Future<ApiCredentials?> read() async => credentials;
}

class _EmptyDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    return const [];
  }
}

class _PendingDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  final Completer<List<DraftPaymentCustomer>> _completer = Completer();

  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) {
    return _completer.future;
  }

  void complete() {
    _completer.complete(const []);
  }
}

CustomerCallStore _testCustomerCallStore() {
  return CustomerCallStore(
    customerSource: _EmptyDraftPaymentCustomerSource(),
    automaticDraftCustomerRefreshEnabled: false,
  );
}

ErpNextSession _testSession() {
  return ErpNextSession(
    sessionId: 'saved-test-session',
    userId: 'agent@example.com',
    fullName: 'Test Agent',
    createdAt: DateTime.utc(2026, 7, 24),
  );
}
