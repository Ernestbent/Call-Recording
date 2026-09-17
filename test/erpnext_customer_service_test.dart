import 'dart:convert';

import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = ErpNextSession(
    sessionId: 'saved-sid',
    userId: 'agent@example.com',
    fullName: 'Agent',
    createdAt: DateTime.utc(2026, 7, 24),
  );

  test('fetches unique customers from draft Payment Entries', () async {
    final requests = <http.Request>[];
    final service = ErpNextCustomerService(
      client: MockClient((request) async {
        requests.add(request);

        if (request.url.path.contains('Payment')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'name': 'PAY-1',
                  'party': 'CUST-A',
                  'creation': '2026-08-01 08:15:00',
                },
                {
                  'name': 'PAY-2',
                  'party': 'CUST-A',
                  'creation': '2026-08-03 10:30:00',
                },
                {
                  'name': 'PAY-3',
                  'party': 'CUST-B',
                  'creation': '2026-08-02 09:00:00',
                },
              ],
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'data': [
              {
                'name': 'CUST-A',
                'customer_name': 'Alpha Motors',
                'mobile_no': '+256 755 962 582',
                'image': '/private/files/alpha.jpg',
              },
              {
                'name': 'CUST-B',
                'customer_name': 'No Phone Customer',
                'mobile_no': '',
                'image': null,
              },
            ],
          }),
          200,
        );
      }),
    );

    final customers = await service.fetchDraftPaymentCustomers(session);

    expect(requests, hasLength(2));
    expect(
      requests.every((request) => request.headers['cookie'] == 'sid=saved-sid'),
      isTrue,
    );
    expect(requests.first.url.path, '/api/resource/Payment%20Entry');
    expect(jsonDecode(requests.first.url.queryParameters['fields']!), [
      'name',
      'party',
      'creation',
    ]);
    expect(jsonDecode(requests.first.url.queryParameters['filters']!), [
      ['docstatus', '=', 0],
      ['party_type', '=', 'Customer'],
    ]);
    expect(requests.last.url.path, '/api/resource/Customer');
    expect(jsonDecode(requests.last.url.queryParameters['filters']!), [
      [
        'name',
        'in',
        ['CUST-A', 'CUST-B'],
      ],
    ]);
    expect(customers, hasLength(1));
    expect(customers.single.customerId, 'CUST-A');
    expect(customers.single.customerName, 'Alpha Motors');
    expect(customers.single.phoneNumber, '0755962582');
    expect(customers.single.draftPaymentCount, 2);
    expect(customers.single.paymentEntryIds, ['PAY-1', 'PAY-2']);
    expect(
      customers.single.latestPaymentEntryCreatedAt,
      DateTime(2026, 8, 3, 10, 30),
    );
    expect(
      customers.single.imageUrl,
      'https://accounting.autozonepro.org/private/files/alpha.jpg',
    );
  });

  test(
    'store maps ERPNext customers and authenticates same-site images',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerCallStore(
        customerSource: _FakeDraftPaymentCustomerSource(),
      );

      final count = await store.loadDraftPaymentCustomers(session);

      expect(count, 1);
      expect(store.customers.single.erpNextCustomerId, 'CUST-A');
      expect(store.customers.single.subtitle, '2 draft payment entries');
      expect(
        store.customers.single.latestPaymentEntryCreatedAt,
        DateTime(2026, 8, 3, 10, 30),
      );
      expect(store.customers.single.profileImageHeaders, {
        'Cookie': 'sid=saved-sid',
      });
    },
  );

  test(
    'store restores cached draft customers when ERPNext is unavailable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firstStore = CustomerCallStore(
        customerSource: _FakeDraftPaymentCustomerSource(),
        draftCustomerRefreshInterval: const Duration(hours: 1),
        connectivityChanges: const Stream.empty(),
      );
      await firstStore.loadDraftPaymentCustomers(session);
      firstStore.dispose();

      final offlineStore = CustomerCallStore(
        customerSource: _FailingDraftPaymentCustomerSource(),
        draftCustomerRefreshInterval: const Duration(hours: 1),
        connectivityChanges: const Stream.empty(),
      );
      addTearDown(offlineStore.dispose);

      final count = await offlineStore.loadDraftPaymentCustomers(session);

      expect(count, 1);
      expect(offlineStore.customers.single.erpNextCustomerId, 'CUST-A');
      expect(offlineStore.customers.single.paymentEntryIds, ['PAY-1', 'PAY-2']);
    },
  );

  test(
    'store refreshes draft customers periodically without overlap',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = _CountingDraftPaymentCustomerSource();
      final store = CustomerCallStore(
        customerSource: source,
        draftCustomerRefreshInterval: const Duration(milliseconds: 15),
        connectivityChanges: const Stream.empty(),
      );
      addTearDown(store.dispose);

      await store.loadDraftPaymentCustomers(session);
      await Future<void>.delayed(const Duration(milliseconds: 55));

      expect(source.requestCount, greaterThanOrEqualTo(2));
      expect(source.maximumConcurrentRequests, 1);
    },
  );

  test('reports ERPNext permission errors', () async {
    final service = ErpNextCustomerService(
      client: MockClient((_) async => http.Response('Forbidden', 403)),
    );

    expect(
      () => service.fetchDraftPaymentCustomers(session),
      throwsA(
        isA<ErpNextCustomerFetchException>().having(
          (error) => error.message,
          'message',
          contains('cannot read'),
        ),
      ),
    );
  });
}

class _FakeDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    return [
      DraftPaymentCustomer(
        customerId: 'CUST-A',
        customerName: 'Alpha Motors',
        phoneNumber: '+256700000001',
        imageUrl: 'https://accounting.autozonepro.org/private/files/alpha.jpg',
        draftPaymentCount: 2,
        paymentEntryIds: const ['PAY-1', 'PAY-2'],
        latestPaymentEntryCreatedAt: DateTime(2026, 8, 3, 10, 30),
      ),
    ];
  }
}

class _FailingDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) {
    throw const ErpNextCustomerFetchException('ERPNext is unavailable.');
  }
}

class _CountingDraftPaymentCustomerSource
    extends _FakeDraftPaymentCustomerSource {
  int requestCount = 0;
  int concurrentRequests = 0;
  int maximumConcurrentRequests = 0;

  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    requestCount++;
    concurrentRequests++;
    if (concurrentRequests > maximumConcurrentRequests) {
      maximumConcurrentRequests = concurrentRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    concurrentRequests--;
    return super.fetchDraftPaymentCustomers(session);
  }
}
