import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    store.markCallStarted(
      store.customers.first.phoneNumber,
      startedAt: callStartedAt,
    );
    await Future<void>.delayed(Duration.zero);

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
