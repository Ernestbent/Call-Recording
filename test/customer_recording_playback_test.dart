import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordings from before the latest draft payment are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final draftCreatedAt = DateTime(2026, 7, 24, 12);
    final oldCallStartedAt = draftCreatedAt.subtract(const Duration(days: 2));
    final currentCallStartedAt = draftCreatedAt.add(const Duration(minutes: 5));
    final oldRecording = CallRecordingFile(
      filePath: '/recordings/old-call.m4a',
      fileName: 'old-call.m4a',
      lastModifiedTime: oldCallStartedAt.add(const Duration(seconds: 30)),
    );
    final currentRecording = CallRecordingFile(
      filePath: '/recordings/current-call.m4a',
      fileName: 'current-call.m4a',
      lastModifiedTime: currentCallStartedAt.add(const Duration(seconds: 30)),
    );
    final store = CustomerCallStore(
      initialCustomers: [
        CustomerContact(
          name: 'Test Customer',
          phoneNumber: '0772835195',
          latestPaymentEntryCreatedAt: draftCreatedAt,
          subtitle: 'Draft payment entry',
          statusLabel: 'Ready to call',
          lastCallStartedAt: oldCallStartedAt,
        ),
      ],
    );
    addTearDown(store.dispose);

    expect(
      store.selectBestRecordingForPhone('0772835195', [oldRecording]),
      isNull,
    );
    expect(
      store.selectBestRecordingForPhone('0772835195', [
        oldRecording,
        currentRecording,
      ]),
      same(currentRecording),
    );

    await store.markCallStarted('0772835195', startedAt: currentCallStartedAt);

    expect(
      store.selectBestRecordingForPhone('0772835195', [
        oldRecording,
        currentRecording,
      ]),
      same(currentRecording),
    );
  });

  test(
    'recording after draft uploads when phone-state timestamp is missing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final draftCreatedAt = DateTime(2026, 7, 24, 12);
      final recordingStartedAt = draftCreatedAt.add(const Duration(minutes: 5));
      final recordingEndedAt = recordingStartedAt.add(
        const Duration(seconds: 45),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ServiceStarter.platform, (call) async {
            if (call.method == 'findRecordingsForPhone') {
              return [
                {
                  'filePath': '/recordings/current-call.m4a',
                  'fileName': 'call_20260724120500.m4a',
                  'lastModifiedTime': recordingEndedAt.millisecondsSinceEpoch,
                },
              ];
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ServiceStarter.platform, null);
      });
      final persistence = _FakeCallPersistence();
      final uploader = _FakeRecordingUploader();
      final store = CustomerCallStore(
        callPersistence: persistence,
        recordingUploader: uploader,
        initialCustomers: [
          CustomerContact(
            erpNextCustomerId: 'CUST-TEST-001',
            name: 'Test Customer',
            phoneNumber: '0772835195',
            latestPaymentEntryCreatedAt: draftCreatedAt,
            subtitle: 'Draft payment entry',
            statusLabel: 'Ready to call',
          ),
        ],
      );
      addTearDown(store.dispose);

      final matched = await store.fetchRecordingsForAllCustomers();

      expect(matched, 1);
      expect(uploader.uploadedCalls, hasLength(1));
      expect(
        uploader.uploadedCalls.single.createdAt,
        '2026-07-24T12:05:00.000',
      );
      expect(
        store.customers.single.latestRecording?.filePath,
        '/recordings/current-call.m4a',
      );
    },
  );

  test('only the best recording for an app-started call is uploaded', () async {
    String? playedPath;
    final callStartedAt = DateTime(2026, 7, 24, 12, 0, 20);
    final closestRecordingAt = DateTime(2026, 7, 24, 12, 0, 25);
    final secondRecordingAt = DateTime(2026, 7, 24, 12, 1);
    final unrelatedRecordingAt = DateTime(2026, 7, 24, 12, 10);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ServiceStarter.platform, (call) async {
          if (call.method == 'findRecordingsForPhone') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            if (arguments['phoneNumber'] == '+256 772545948') {
              return [
                {
                  'filePath': '/recordings/closest.m4a',
                  'fileName': 'closest.m4a',
                  'lastModifiedTime': closestRecordingAt.millisecondsSinceEpoch,
                },
                {
                  'filePath': '/recordings/second.m4a',
                  'fileName': 'second.m4a',
                  'lastModifiedTime': secondRecordingAt.millisecondsSinceEpoch,
                },
                {
                  'filePath': '/recordings/unrelated.m4a',
                  'fileName': 'unrelated.m4a',
                  'lastModifiedTime':
                      unrelatedRecordingAt.millisecondsSinceEpoch,
                },
              ];
            }
            return <Map<String, Object>>[];
          }

          if (call.method == 'playRecording') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            playedPath = arguments['filePath'] as String;
            return true;
          }
          if (call.method == 'pauseRecording' ||
              call.method == 'resumeRecording') {
            return true;
          }

          return null;
        });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ServiceStarter.platform, null);
    });

    SharedPreferences.setMockInitialValues({});
    final persistence = _FakeCallPersistence();
    final uploader = _FakeRecordingUploader();
    final store = CustomerCallStore(
      callPersistence: persistence,
      recordingUploader: uploader,
      initialCustomers: const [
        CustomerContact(
          name: 'Othieno Benedict Ernest',
          phoneNumber: '+256 772545948',
          subtitle: 'Draft payment entry',
          statusLabel: 'Ready to call',
        ),
      ],
    );
    await store.markCallStarted(
      store.customers.first.phoneNumber,
      startedAt: callStartedAt,
    );

    final matchedCustomers = await store.fetchRecordingsForAllCustomers();

    expect(matchedCustomers, 1);
    expect(store.customers.first.availableRecordings, hasLength(1));
    expect(
      store.customers.first.latestRecording?.filePath,
      '/recordings/closest.m4a',
    );
    expect(
      store.customers.first.availableRecordings.map(
        (recording) => recording.filePath,
      ),
      isNot(contains('/recordings/unrelated.m4a')),
    );
    expect(persistence.savedCalls, hasLength(1));
    expect(
      persistence.savedCalls.first['audio_path'],
      '/recordings/closest.m4a',
    );
    expect(persistence.savedCalls.first['phone_number'], '+256 772545948');
    expect(
      persistence.savedCalls.every((call) => call['status'] == 'uploaded'),
      isTrue,
    );
    expect(uploader.uploadedCalls, hasLength(1));
    final savedSessionIds = persistence.savedCalls
        .map((call) => call['session_id'])
        .toSet();

    await store.fetchRecordingsForAllCustomers();

    expect(persistence.savedCalls, hasLength(1));
    expect(
      persistence.savedCalls.map((call) => call['session_id']).toSet(),
      savedSessionIds,
    );
    expect(uploader.uploadedCalls, hasLength(1));

    final recording = store.customers.first.availableRecordings.single;
    final didStart = await store.playRecording(recording);

    expect(didStart, isTrue);
    expect(playedPath, '/recordings/closest.m4a');
    expect(store.isPlayingRecording(recording), isTrue);

    final didPause = await store.playRecording(recording);

    expect(didPause, isTrue);
    expect(store.isActiveRecording(recording), isTrue);
    expect(store.isPlayingRecording(recording), isFalse);

    final didResume = await store.playRecording(recording);

    expect(didResume, isTrue);
    expect(store.isPlayingRecording(recording), isTrue);
  });
}

class _FakeRecordingUploader implements RecordingUploader {
  final List<CallModel> uploadedCalls = [];

  @override
  bool get isConfigured => true;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
    String? agentEmail,
  }) async {
    uploadedCalls.add(call);
    return RecordingUploadResult(
      uploadId: '${uploadedCalls.length}',
      message: 'Uploaded.',
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
