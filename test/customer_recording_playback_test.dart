import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only recordings near an app-started call are retained', () async {
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
    final store = CustomerCallStore(callPersistence: persistence);
    store.markCallStarted(
      store.customers.first.phoneNumber,
      startedAt: callStartedAt,
    );
    await Future<void>.delayed(Duration.zero);

    final matchedCustomers = await store.fetchRecordingsForAllCustomers();

    expect(matchedCustomers, 1);
    expect(store.customers.first.availableRecordings, hasLength(2));
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
      persistence.savedCalls.single['audio_path'],
      '/recordings/closest.m4a',
    );
    expect(persistence.savedCalls.single['phone_number'], '+256 772545948');
    expect(persistence.savedCalls.single['status'], 'pending');

    await store.fetchRecordingsForAllCustomers();

    expect(
      persistence.savedCalls.last['session_id'],
      persistence.savedCalls.first['session_id'],
    );

    final recording = store.customers.first.availableRecordings.last;
    final didStart = await store.playRecording(recording);

    expect(didStart, isTrue);
    expect(playedPath, '/recordings/second.m4a');
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

class _FakeCallPersistence implements CallPersistence {
  final List<Map<String, dynamic>> savedCalls = [];

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {
    savedCalls.add(Map<String, dynamic>.from(call));
  }
}
