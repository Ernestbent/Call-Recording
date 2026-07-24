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
                {'name': 'PAY-1', 'party': 'CUST-A'},
                {'name': 'PAY-2', 'party': 'CUST-A'},
                {'name': 'PAY-3', 'party': 'CUST-B'},
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
      expect(store.customers.single.profileImageHeaders, {
        'Cookie': 'sid=saved-sid',
      });
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
    return const [
      DraftPaymentCustomer(
        customerId: 'CUST-A',
        customerName: 'Alpha Motors',
        phoneNumber: '+256700000001',
        imageUrl: 'https://accounting.autozonepro.org/private/files/alpha.jpg',
        draftPaymentCount: 2,
      ),
    ];
  }
}
