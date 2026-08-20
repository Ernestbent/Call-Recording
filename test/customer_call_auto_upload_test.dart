import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'matched recording uploads automatically when a call completes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final persistence = _FakeCallPersistence();
      final uploader = _FakeRecordingUploader();
      final store = CustomerCallStore(
        callPersistence: persistence,
        recordingUploader: uploader,
        initialCustomers: const [
          CustomerContact(
            erpNextCustomerId: 'CUST-TEST-001',
            name: 'Test Customer',
            phoneNumber: '0772835195',
            paymentEntryIds: ['PAY-1', 'PAY-2'],
            subtitle: '1 draft payment entry',
            statusLabel: 'Ready to call',
          ),
        ],
      );
      final startedAt = DateTime(2026, 8, 3, 12);
      final endedAt = startedAt.add(const Duration(seconds: 45));
      final recording = CallRecordingFile(
        filePath: '/recordings/test-call.mp3',
        fileName: 'test-call.mp3',
        lastModifiedTime: endedAt,
      );

      store.markCallStarted('0772835195', startedAt: startedAt);
      await store.markCallCompleted(
        phoneNumber: '0772835195',
        callEndedAt: endedAt,
        recording: recording,
      );

      expect(uploader.uploadedCalls, hasLength(1));
      expect(uploader.customerIds, ['CUST-TEST-001']);
      expect(persistence.savedCalls.single['status'], 'uploaded');
      expect(
        store.recordingUploadState(recording),
        RecordingUploadState.uploaded,
      );
      expect(store.customers.single.statusLabel, 'Recording uploaded');
      expect(store.customersToCall, isEmpty);

      final source = _FakeDraftPaymentCustomerSource([
        _draftPaymentCustomer(['PAY-1', 'PAY-2']),
      ]);
      final refreshedStore = CustomerCallStore(customerSource: source);
      await refreshedStore.loadDraftPaymentCustomers(_session);
      expect(refreshedStore.customersToCall, isEmpty);

      source.customers = [
        _draftPaymentCustomer(['PAY-1', 'PAY-2', 'PAY-3']),
      ];
      await refreshedStore.refreshDraftPaymentCustomers();
      expect(refreshedStore.customersToCall, hasLength(1));
      expect(refreshedStore.customersToCall.single.draftPaymentCount, 1);
      expect(
        refreshedStore.customersToCall.single.subtitle,
        '1 draft payment entry',
      );
    },
  );

  test('already-uploaded call hides its payment entries after upgrade', () async {
    SharedPreferences.setMockInitialValues({});
    final startedAt = DateTime(2026, 8, 3, 12);
    final endedAt = startedAt.add(const Duration(seconds: 45));
    final recording = CallRecordingFile(
      filePath: '/recordings/test-call.mp3',
      fileName: 'test-call.mp3',
      lastModifiedTime: endedAt,
    );
    final persistence = _FakeCallPersistence()
      ..savedCalls.add({
        'session_id':
            'call_0772835195_${startedAt.millisecondsSinceEpoch}_${endedAt.millisecondsSinceEpoch}',
        'status': 'uploaded',
      });
    final uploader = _FakeRecordingUploader();
    final store = CustomerCallStore(
      callPersistence: persistence,
      recordingUploader: uploader,
      initialCustomers: const [
        CustomerContact(
          erpNextCustomerId: 'CUST-TEST-001',
          name: 'Test Customer',
          phoneNumber: '0772835195',
          paymentEntryIds: ['PAY-1', 'PAY-2'],
          subtitle: '2 draft payment entries',
          statusLabel: 'Ready to call',
        ),
      ],
    );

    store.markCallStarted('0772835195', startedAt: startedAt);
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: endedAt,
      recording: recording,
    );

    expect(uploader.uploadedCalls, isEmpty);
    expect(store.customersToCall, isEmpty);

    final refreshedStore = CustomerCallStore(
      customerSource: _FakeDraftPaymentCustomerSource([
        _draftPaymentCustomer(['PAY-1', 'PAY-2']),
      ]),
    );
    await refreshedStore.loadDraftPaymentCustomers(_session);
    expect(refreshedStore.customersToCall, isEmpty);
  });

  test('duplicate completion events upload only one recording', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = _FakeCallPersistence();
    final uploader = _FakeRecordingUploader();
    final store = CustomerCallStore(
      callPersistence: persistence,
      recordingUploader: uploader,
      initialCustomers: const [
        CustomerContact(
          erpNextCustomerId: 'CUST-TEST-001',
          name: 'Test Customer',
          phoneNumber: '0772835195',
          subtitle: '1 draft payment entry',
          statusLabel: 'Ready to call',
        ),
      ],
    );
    final startedAt = DateTime(2026, 8, 3, 12);
    final endedAt = startedAt.add(const Duration(seconds: 45));
    final serviceRecording = CallRecordingFile(
      filePath: '/recordings/service-call.m4a',
      fileName: 'service-call.m4a',
      lastModifiedTime: endedAt,
    );
    final dialerRecording = CallRecordingFile(
      filePath: '/recordings/dialer-call.m4a',
      fileName: 'dialer-call.m4a',
      lastModifiedTime: endedAt.add(const Duration(seconds: 1)),
    );

    store.markCallStarted('0772835195', startedAt: startedAt);
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: endedAt,
      recording: serviceRecording,
    );
    store.markCallStarted(
      '0772835195',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    );
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: endedAt.add(const Duration(seconds: 1)),
      recording: dialerRecording,
    );

    expect(uploader.uploadedCalls, hasLength(1));
    expect(persistence.savedCalls, hasLength(1));
    expect(store.customers.single.availableRecordings, [serviceRecording]);
    expect(store.customers.single.matchingRecordingsCount, 1);
  });
}

final _session = ErpNextSession(
  sessionId: 'test-session',
  userId: 'agent@example.com',
  fullName: 'Agent',
  createdAt: DateTime.utc(2026, 8, 3),
);

DraftPaymentCustomer _draftPaymentCustomer(List<String> paymentEntryIds) {
  return DraftPaymentCustomer(
    customerId: 'CUST-TEST-001',
    customerName: 'Test Customer',
    phoneNumber: '0772835195',
    imageUrl: null,
    draftPaymentCount: paymentEntryIds.length,
    paymentEntryIds: paymentEntryIds,
  );
}

class _FakeDraftPaymentCustomerSource implements DraftPaymentCustomerSource {
  List<DraftPaymentCustomer> customers;

  _FakeDraftPaymentCustomerSource(this.customers);

  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async => customers;
}

class _FakeRecordingUploader implements RecordingUploader {
  final List<CallModel> uploadedCalls = [];
  final List<String?> customerIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
    String? agentEmail,
  }) async {
    uploadedCalls.add(call);
    customerIds.add(customerId);
    return const RecordingUploadResult(
      uploadId: '1',
      message: 'Recording uploaded successfully.',
    );
  }
}

class _FakeCallPersistence implements CallPersistence {
  final List<Map<String, dynamic>> savedCalls = [];

  @override
  Future<Map<String, dynamic>?> getCall(String sessionId) async {
    for (final call in savedCalls.reversed) {
      if (call['session_id'] == sessionId) return call;
    }
    return null;
  }

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {
    savedCalls.add(Map<String, dynamic>.from(call));
  }

  @override
  Future<void> updateStatus(String sessionId, String status) async {
    final call = await getCall(sessionId);
    call?['status'] = status;
  }
}
