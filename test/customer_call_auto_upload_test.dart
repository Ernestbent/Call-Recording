import 'dart:async';
import 'dart:convert';

import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/models/persisted_call_session.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

      await store.markCallStarted('0772835195', startedAt: startedAt);
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

    await store.markCallStarted('0772835195', startedAt: startedAt);
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

    await store.markCallStarted('0772835195', startedAt: startedAt);
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: endedAt,
      recording: serviceRecording,
    );
    await store.markCallStarted(
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

  test(
    'failed upload retries automatically without reopening the app',
    () async {
      SharedPreferences.setMockInitialValues({});
      final uploader = _FakeRecordingUploader(failuresBeforeSuccess: 1);
      final store = CustomerCallStore(
        callPersistence: _FakeCallPersistence(),
        customerSource: _FakeDraftPaymentCustomerSource([
          _draftPaymentCustomer(['PAY-RETRY']),
        ]),
        recordingUploader: uploader,
        automaticUploadRetryDelays: const [Duration(milliseconds: 10)],
      );
      addTearDown(store.dispose);
      await store.loadDraftPaymentCustomers(_session);

      final startedAt = DateTime(2026, 8, 3, 12);
      final endedAt = startedAt.add(const Duration(seconds: 45));
      final recording = CallRecordingFile(
        filePath: '/recordings/retry-call.m4a',
        fileName: 'retry-call.m4a',
        lastModifiedTime: endedAt,
      );

      await store.markCallStarted('0772835195', startedAt: startedAt);
      await store.markCallCompleted(
        phoneNumber: '0772835195',
        callEndedAt: endedAt,
        recording: recording,
      );

      expect(uploader.uploadedCalls, hasLength(1));
      expect(
        store.recordingUploadState(recording),
        RecordingUploadState.failed,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(uploader.uploadedCalls, hasLength(2));
      expect(
        store.recordingUploadState(recording),
        RecordingUploadState.uploaded,
      );
    },
  );

  test(
    'offline pauses retries and connectivity restoration retries immediately',
    () async {
      SharedPreferences.setMockInitialValues({});
      final connectivity = StreamController<List<ConnectivityResult>>();
      final uploader = _FakeRecordingUploader(failuresBeforeSuccess: 1);
      final store = CustomerCallStore(
        callPersistence: _FakeCallPersistence(),
        customerSource: _FakeDraftPaymentCustomerSource([
          _draftPaymentCustomer(['PAY-CONNECTIVITY']),
        ]),
        recordingUploader: uploader,
        automaticUploadRetryDelays: const [Duration(milliseconds: 10)],
        connectivityChanges: connectivity.stream,
      );
      addTearDown(() async {
        store.dispose();
        await connectivity.close();
      });
      await store.loadDraftPaymentCustomers(_session);

      final startedAt = DateTime(2026, 8, 3, 12);
      final endedAt = startedAt.add(const Duration(seconds: 45));
      final recording = CallRecordingFile(
        filePath: '/recordings/connectivity-call.m4a',
        fileName: 'connectivity-call.m4a',
        lastModifiedTime: endedAt,
      );

      await store.markCallStarted('0772835195', startedAt: startedAt);
      await store.markCallCompleted(
        phoneNumber: '0772835195',
        callEndedAt: endedAt,
        recording: recording,
      );
      expect(uploader.uploadedCalls, hasLength(1));

      connectivity.add(const [ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        uploader.uploadedCalls,
        hasLength(1),
        reason: 'No POST retry should run while the device is offline.',
      );

      connectivity.add(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(uploader.uploadedCalls, hasLength(2));
      expect(
        store.recordingUploadState(recording),
        RecordingUploadState.uploaded,
      );
    },
  );

  test('stale persisted call is not restored for a newer draft', () async {
    final draftCreatedAt = DateTime(2026, 8, 3, 12);
    final staleCallStartedAt = draftCreatedAt.subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'customer_0772835195_last_call_started_at':
          staleCallStartedAt.millisecondsSinceEpoch,
      'customer_0772835195_last_call_ended_at': staleCallStartedAt
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    });
    final store = CustomerCallStore(
      customerSource: _FakeDraftPaymentCustomerSource([
        _draftPaymentCustomer([
          'PAY-CURRENT',
        ], latestPaymentEntryCreatedAt: draftCreatedAt),
      ]),
    );
    addTearDown(store.dispose);

    await store.loadDraftPaymentCustomers(_session);

    expect(store.customers.single.lastCallStartedAt, isNull);
    expect(store.customers.single.lastCallEndedAt, isNull);
    expect(store.matchedRecordingsCount, 0);
  });

  test('waiting session remains after customer leaves draft list', () async {
    SharedPreferences.setMockInitialValues({});
    final draftCreatedAt = DateTime(2026, 8, 3, 11);
    final source = _FakeDraftPaymentCustomerSource([
      _draftPaymentCustomer([
        'PAY-WAITING',
      ], latestPaymentEntryCreatedAt: draftCreatedAt),
    ]);
    final store = CustomerCallStore(
      customerSource: source,
      recordingUploader: _FakeRecordingUploader(),
    );
    addTearDown(store.dispose);
    await store.loadDraftPaymentCustomers(_session);

    final startedAt = DateTime(2026, 8, 3, 12);
    await store.markCallStarted('0772835195', startedAt: startedAt);
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: startedAt.add(const Duration(minutes: 1)),
      recording: null,
    );

    source.customers = [];
    await store.refreshDraftPaymentCustomers();

    expect(store.customers, isEmpty);
    expect(store.callSessions, hasLength(1));
    expect(
      store.callSessions.single.status,
      PersistedCallStatus.waitingForRecording,
    );
  });

  test('pending upload resumes after restart and draft removal', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = _FakeCallPersistence();
    final draftCreatedAt = DateTime(2026, 8, 3, 11);
    final source = _FakeDraftPaymentCustomerSource([
      _draftPaymentCustomer([
        'PAY-PERSISTED',
      ], latestPaymentEntryCreatedAt: draftCreatedAt),
    ]);
    final firstUploader = _FakeRecordingUploader(failuresBeforeSuccess: 1);
    final firstStore = CustomerCallStore(
      callPersistence: persistence,
      customerSource: source,
      recordingUploader: firstUploader,
      automaticUploadRetryDelays: const [Duration(hours: 1)],
    );
    await firstStore.loadDraftPaymentCustomers(_session);

    final startedAt = DateTime(2026, 8, 3, 12);
    final recording = CallRecordingFile(
      filePath: '/recordings/persisted-retry.m4a',
      fileName: 'call_20260803120000.m4a',
      lastModifiedTime: startedAt.add(const Duration(minutes: 1)),
    );
    await firstStore.markCallStarted('0772835195', startedAt: startedAt);
    await firstStore.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: recording.lastModifiedTime,
      recording: recording,
    );
    expect(
      firstStore.callSessions.single.status,
      PersistedCallStatus.pendingUpload,
    );
    firstStore.dispose();

    source.customers = [];
    final resumedUploader = _FakeRecordingUploader();
    final resumedStore = CustomerCallStore(
      callPersistence: persistence,
      customerSource: source,
      recordingUploader: resumedUploader,
      automaticUploadRetryDelays: const [Duration(hours: 1)],
    );
    addTearDown(resumedStore.dispose);
    await resumedStore.hydrate();
    await resumedStore.loadDraftPaymentCustomers(_session);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(resumedStore.customers, isEmpty);
    expect(resumedUploader.uploadedCalls, hasLength(1));
    expect(
      resumedStore.callSessions.single.status,
      PersistedCallStatus.uploaded,
    );
  });

  test(
    'pending ledger upload uses its saved start time after a newer draft',
    () async {
      final startedAt = DateTime(2026, 9, 15, 14, 26, 45);
      final endedAt = startedAt.add(const Duration(minutes: 2, seconds: 3));
      final session = PersistedCallSession(
        id: 'call_0708463342_${startedAt.millisecondsSinceEpoch}',
        customerId: 'CUST-BRIAN',
        customerName: 'Brian And Sons Motors',
        phoneNumber: '0708463342',
        paymentEntryIds: const ['PAY-NEWER'],
        draftCreatedAt: startedAt.add(const Duration(days: 1)),
        startedAt: startedAt,
        endedAt: endedAt,
        recordingPath: '/recordings/brian.aac',
        recordingName: 'brian.aac',
        recordingModifiedAt: endedAt,
        status: PersistedCallStatus.pendingUpload,
        lastError: 'The call start time is missing.',
      );
      SharedPreferences.setMockInitialValues({
        'persistent_call_session_ledger': jsonEncode([session.toJson()]),
      });
      final uploader = _FakeRecordingUploader();
      final store = CustomerCallStore(
        callPersistence: _FakeCallPersistence(),
        customerSource: _FakeDraftPaymentCustomerSource([]),
        recordingUploader: uploader,
      );
      addTearDown(store.dispose);

      await store.hydrate();
      await store.loadDraftPaymentCustomers(_session);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(uploader.uploadedCalls, hasLength(1));
      expect(
        uploader.uploadedCalls.single.createdAt,
        startedAt.toIso8601String(),
      );
      expect(store.callSessions.single.status, PersistedCallStatus.uploaded);
      expect(store.callSessions.single.lastError, isNull);
    },
  );

  test('recording discovery resumes after restart and draft removal', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = _FakeCallPersistence();
    final draftCreatedAt = DateTime(2026, 8, 3, 11);
    final source = _FakeDraftPaymentCustomerSource([
      _draftPaymentCustomer([
        'PAY-DISCOVERY',
      ], latestPaymentEntryCreatedAt: draftCreatedAt),
    ]);
    final firstStore = CustomerCallStore(
      callPersistence: persistence,
      customerSource: source,
      recordingUploader: _FakeRecordingUploader(),
    );
    await firstStore.loadDraftPaymentCustomers(_session);
    final startedAt = DateTime(2026, 8, 3, 12);
    await firstStore.markCallStarted('0772835195', startedAt: startedAt);
    await firstStore.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: startedAt.add(const Duration(minutes: 1)),
      recording: null,
    );
    source.customers = [];
    await firstStore.refreshDraftPaymentCustomers();
    firstStore.dispose();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ServiceStarter.platform, (call) async {
          if (call.method == 'findRecordingsForPhone') {
            return [
              {
                'filePath': '/recordings/discovered-after-restart.m4a',
                'fileName': 'call_20260803120000.m4a',
                'lastModifiedTime': startedAt
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
              },
            ];
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ServiceStarter.platform, null);
    });
    final uploader = _FakeRecordingUploader();
    final resumedStore = CustomerCallStore(
      callPersistence: persistence,
      customerSource: source,
      recordingUploader: uploader,
    );
    addTearDown(resumedStore.dispose);
    await resumedStore.hydrate();
    await resumedStore.loadDraftPaymentCustomers(_session);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(resumedStore.customers, isEmpty);
    expect(uploader.uploadedCalls, hasLength(1));
    expect(
      resumedStore.callSessions.single.status,
      PersistedCallStatus.uploaded,
    );
    expect(
      resumedStore.callSessions.single.recordingPath,
      '/recordings/discovered-after-restart.m4a',
    );
  });

  test('legacy call timestamps become permanent waiting sessions', () async {
    final draftCreatedAt = DateTime(2026, 8, 3, 11);
    final startedAt = DateTime(2026, 8, 3, 12);
    SharedPreferences.setMockInitialValues({
      'draft_payment_customer_cache_agent': jsonEncode([
        {
          'customer_id': 'CUST-TEST-001',
          'customer_name': 'Test Customer',
          'phone_number': '0772835195',
          'payment_entry_ids': ['PAY-LEGACY'],
          'latest_payment_entry_created_at': draftCreatedAt.toIso8601String(),
        },
      ]),
      'customer_0772835195_last_call_started_at':
          startedAt.millisecondsSinceEpoch,
      'customer_0772835195_last_call_ended_at': startedAt
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    });
    final store = CustomerCallStore(
      callPersistence: _FakeCallPersistence(),
      automaticDraftCustomerRefreshEnabled: false,
    );
    addTearDown(store.dispose);

    await store.hydrate();

    expect(store.callSessions, hasLength(1));
    expect(store.callSessions.single.customerName, 'Test Customer');
    expect(
      store.callSessions.single.status,
      PersistedCallStatus.waitingForRecording,
    );
  });

  test('waiting session stops scanning after the discovery window', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 8, 3, 12, 30);
    final store = CustomerCallStore(
      callPersistence: _FakeCallPersistence(),
      customerSource: _FakeDraftPaymentCustomerSource([
        _draftPaymentCustomer(['PAY-MISSING']),
      ]),
      automaticDraftCustomerRefreshEnabled: false,
      recordingDiscoveryTimeout: const Duration(minutes: 15),
      now: () => now,
    );
    addTearDown(store.dispose);
    await store.loadDraftPaymentCustomers(_session);

    final startedAt = now.subtract(const Duration(minutes: 20));
    await store.markCallStarted('0772835195', startedAt: startedAt);
    await store.markCallCompleted(
      phoneNumber: '0772835195',
      callEndedAt: startedAt.add(const Duration(minutes: 1)),
      recording: null,
    );
    await store.refreshPendingSessions();

    expect(
      store.callSessions.single.status,
      PersistedCallStatus.recordingNotFound,
    );
    expect(store.activeCallSessions, isEmpty);
    expect(store.sessionHistory, hasLength(1));
  });

  test('clearing history preserves unresolved uploads', () async {
    final now = DateTime(2026, 8, 3, 12, 30);
    final sessions = [
      _persistedSession(
        id: 'uploaded',
        status: PersistedCallStatus.uploaded,
        statusChangedAt: now,
      ),
      _persistedSession(
        id: 'missing',
        status: PersistedCallStatus.recordingNotFound,
        statusChangedAt: now,
      ),
      _persistedSession(
        id: 'pending',
        status: PersistedCallStatus.pendingUpload,
        statusChangedAt: now.subtract(const Duration(days: 60)),
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'persistent_call_session_ledger': jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      ),
    });
    final persistence = _FakeCallPersistence()
      ..savedCalls.addAll([
        {
          'session_id': 'uploaded',
          'audio_path': '/recordings/uploaded.aac',
          'status': 'uploaded',
        },
        {
          'session_id': 'legacy-duplicate',
          'audio_path': '/recordings/uploaded.aac',
          'status': 'uploaded',
        },
      ]);
    final store = CustomerCallStore(
      callPersistence: persistence,
      automaticDraftCustomerRefreshEnabled: false,
      now: () => now,
    );
    addTearDown(store.dispose);
    await store.hydrate();

    final removed = await store.clearResolvedSessionHistory();

    expect(removed, 2);
    expect(store.callSessions.map((session) => session.id), ['pending']);
    expect(store.activeCallSessions, hasLength(1));
    expect(store.sessionHistory, isEmpty);
    expect(persistence.savedCalls, isEmpty);
  });

  test('resolved history older than 30 days is pruned on startup', () async {
    final now = DateTime(2026, 8, 3, 12, 30);
    final sessions = [
      _persistedSession(
        id: 'old-upload',
        status: PersistedCallStatus.uploaded,
        statusChangedAt: now.subtract(const Duration(days: 31)),
      ),
      _persistedSession(
        id: 'recent-upload',
        status: PersistedCallStatus.uploaded,
        statusChangedAt: now.subtract(const Duration(days: 2)),
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'persistent_call_session_ledger': jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      ),
    });
    final store = CustomerCallStore(
      callPersistence: _FakeCallPersistence(),
      automaticDraftCustomerRefreshEnabled: false,
      now: () => now,
    );
    addTearDown(store.dispose);

    await store.hydrate();

    expect(store.callSessions.map((session) => session.id), ['recent-upload']);
  });

  test(
    'unlinked legacy rows never enter Sessions or the upload queue',
    () async {
      final now = DateTime(2026, 9, 16, 16);
      final linked = _persistedSession(
        id: 'linked',
        status: PersistedCallStatus.pendingUpload,
        statusChangedAt: now,
      );
      final unlinked = PersistedCallSession(
        id: 'unlinked',
        customerId: null,
        customerName: '0700000000',
        phoneNumber: '0700000000',
        paymentEntryIds: const [],
        draftCreatedAt: null,
        startedAt: now.subtract(const Duration(days: 20)),
        endedAt: now
            .subtract(const Duration(days: 20))
            .add(const Duration(minutes: 1)),
        recordingPath: '/recordings/unlinked.aac',
        recordingName: 'unlinked.aac',
        recordingModifiedAt: now.subtract(const Duration(days: 20)),
        status: PersistedCallStatus.pendingUpload,
        statusChangedAt: now.subtract(const Duration(days: 20)),
        lastError: null,
      );
      SharedPreferences.setMockInitialValues({
        'persistent_call_session_ledger': jsonEncode([
          linked.toJson(),
          unlinked.toJson(),
        ]),
      });
      final store = CustomerCallStore(
        callPersistence: _FakeCallPersistence(),
        automaticDraftCustomerRefreshEnabled: false,
        now: () => now,
      );
      addTearDown(store.dispose);

      await store.hydrate();

      expect(store.callSessions.map((session) => session.id), ['linked']);
      expect(store.pendingRecordingUploadsCount, 1);
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('persistent_call_session_ledger')!)
              as List;
      expect(saved, hasLength(1));
      expect((saved.single as Map)['id'], 'linked');
    },
  );
}

final _session = ErpNextSession(
  sessionId: 'test-session',
  userId: 'agent@example.com',
  fullName: 'Agent',
  createdAt: DateTime.utc(2026, 8, 3),
);

DraftPaymentCustomer _draftPaymentCustomer(
  List<String> paymentEntryIds, {
  DateTime? latestPaymentEntryCreatedAt,
}) {
  return DraftPaymentCustomer(
    customerId: 'CUST-TEST-001',
    customerName: 'Test Customer',
    phoneNumber: '0772835195',
    imageUrl: null,
    draftPaymentCount: paymentEntryIds.length,
    paymentEntryIds: paymentEntryIds,
    latestPaymentEntryCreatedAt: latestPaymentEntryCreatedAt,
  );
}

PersistedCallSession _persistedSession({
  required String id,
  required PersistedCallStatus status,
  required DateTime statusChangedAt,
}) {
  final startedAt = statusChangedAt.subtract(const Duration(minutes: 1));
  final hasRecording =
      status != PersistedCallStatus.recordingNotFound &&
      status != PersistedCallStatus.waitingForRecording;
  return PersistedCallSession(
    id: id,
    customerId: 'CUST-TEST-001',
    customerName: 'Test Customer',
    phoneNumber: '0772835195',
    paymentEntryIds: const ['PAY-TEST'],
    draftCreatedAt: startedAt.subtract(const Duration(hours: 1)),
    startedAt: startedAt,
    endedAt: statusChangedAt,
    recordingPath: hasRecording ? '/recordings/$id.aac' : null,
    recordingName: hasRecording ? '$id.aac' : null,
    recordingModifiedAt: hasRecording ? statusChangedAt : null,
    status: status,
    statusChangedAt: statusChangedAt,
    lastError: null,
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
  _FakeRecordingUploader({this.failuresBeforeSuccess = 0});

  final List<CallModel> uploadedCalls = [];
  final List<String?> customerIds = [];
  final int failuresBeforeSuccess;

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
    if (uploadedCalls.length <= failuresBeforeSuccess) {
      throw const RecordingUploadException(
        'Recording is still being finalized.',
      );
    }
    return const RecordingUploadResult(
      uploadId: '1',
      message: 'Recording uploaded successfully.',
    );
  }
}

class _FakeCallPersistence implements CallPersistence {
  final List<Map<String, dynamic>> savedCalls = [];

  @override
  Future<void> deleteCalls(
    Iterable<String> sessionIds, {
    Iterable<String> audioPaths = const [],
  }) async {
    final ids = sessionIds.toSet();
    final paths = audioPaths.toSet();
    savedCalls.removeWhere(
      (call) =>
          ids.contains(call['session_id']) ||
          paths.contains(call['audio_path']),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getAllCalls() async =>
      List.unmodifiable(savedCalls);

  @override
  Future<Map<String, dynamic>?> getCall(String sessionId) async {
    for (final call in savedCalls.reversed) {
      if (call['session_id'] == sessionId) return call;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getCallByAudioPath(String audioPath) async {
    for (final call in savedCalls.reversed) {
      if (call['audio_path'] == audioPath) return call;
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
