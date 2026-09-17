import 'dart:io';

import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/api_credentials.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'uploads recording and call metadata as authenticated multipart',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'recording-upload-test-',
      );
      final recording = File('${tempDirectory.path}/sample.mp3');
      await recording.writeAsBytes([0x49, 0x44, 0x33, 0x04]);
      addTearDown(() => tempDirectory.delete(recursive: true));

      late http.Request capturedRequest;
      final uploader = HttpRecordingUploader(
        endpoint: Uri.parse('https://example.test/api/recordings'),
        credentialProvider: _TestCredentialManager(),
        fileInspector: const _ReadyRecordingInspector(),
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            '{"ok":true,"duplicate":false,'
            '"message":"Call log synced.",'
            '"call_log":{"id":123,'
            '"audio_url":"/mobile-call-logs/123/audio/"}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final call = CallModel(
        sessionId: 'call-123',
        phoneNumber: '0755962582',
        callType: 'outgoing',
        duration: 17,
        audioPath: recording.path,
        status: 'pending',
        createdAt: '2026-07-24T13:00:20.000',
      );

      final result = await uploader.upload(
        call: call,
        customerId: 'CUST-001',
        agentEmail: 'agent@example.com',
      );

      expect(result.uploadId, '123');
      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url,
        Uri.parse('https://example.test/api/recordings'),
      );
      expect(
        capturedRequest.headers['authorization'],
        'token test-api-key:test-api-secret',
      );
      expect(
        capturedRequest.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(capturedRequest.body, contains('name="audio_file"'));
      expect(capturedRequest.body, contains('filename="sample.mp3"'));
      expect(capturedRequest.body, contains('name="device_local_id"'));
      expect(capturedRequest.body, contains('call-123'));
      expect(capturedRequest.body, contains('name="mobile_no"'));
      expect(capturedRequest.body, contains('0755962582'));
      expect(capturedRequest.body, contains('name="customer_id"'));
      expect(capturedRequest.body, contains('CUST-001'));
      expect(capturedRequest.body, contains('name="call_date"'));
      expect(capturedRequest.body, contains('2026-07-24'));
      expect(capturedRequest.body, contains('name="call_time"'));
      expect(capturedRequest.body, contains('13:00:20'));
      expect(capturedRequest.body, contains('name="duration_seconds"'));
      expect(capturedRequest.body, contains('name="agent_username"'));
      expect(capturedRequest.body, contains('agent@example.com'));
    },
  );

  test('refreshes matching saved credentials from the agent catalog', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-upload-refresh-test-',
    );
    final recording = File('${tempDirectory.path}/sample.mp3');
    await recording.writeAsBytes([0x49, 0x44, 0x33, 0x04]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    late http.Request capturedRequest;
    final uploader = HttpRecordingUploader(
      endpoint: Uri.parse('https://example.test/api/recordings'),
      fileInspector: const _ReadyRecordingInspector(),
      credentialProvider: _TestCredentialManager(
        saved: const ApiCredentials(
          email: 'agent@example.com',
          apiKey: 'old-api-key',
          apiSecret: 'old-api-secret',
        ),
        activated: const ApiCredentials(
          email: 'agent@example.com',
          apiKey: 'fresh-api-key',
          apiSecret: 'fresh-api-secret',
        ),
      ),
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          '{"ok":true,"call_log":{"id":123}}',
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final call = CallModel(
      sessionId: 'call-123',
      phoneNumber: '0755962582',
      callType: 'outgoing',
      duration: 17,
      audioPath: recording.path,
      status: 'pending',
      createdAt: '2026-07-24T13:00:20.000',
    );

    await uploader.upload(
      call: call,
      customerId: 'CUST-001',
      agentEmail: 'agent@example.com',
    );

    expect(
      capturedRequest.headers['authorization'],
      'token fresh-api-key:fresh-api-secret',
    );
    expect(capturedRequest.body, contains('agent@example.com'));
  });

  test('rejects credentials belonging to a different signed-in user', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-upload-user-match-test-',
    );
    final recording = File('${tempDirectory.path}/sample.mp3');
    await recording.writeAsBytes([0x49, 0x44, 0x33, 0x04]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    var requestWasSent = false;
    final uploader = HttpRecordingUploader(
      endpoint: Uri.parse('https://example.test/api/recordings'),
      credentialProvider: _TestCredentialManager(
        activated: const ApiCredentials(
          email: 'other@example.com',
          apiKey: 'other-key',
          apiSecret: 'other-secret',
        ),
      ),
      fileInspector: const _ReadyRecordingInspector(),
      client: MockClient((request) async {
        requestWasSent = true;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      uploader.upload(
        call: CallModel(
          sessionId: 'call-user-mismatch',
          phoneNumber: '0755962582',
          callType: 'outgoing',
          duration: 17,
          audioPath: recording.path,
          status: 'pending',
          createdAt: '2026-07-24T13:00:20.000',
        ),
        customerId: 'CUST-001',
        agentEmail: 'agent@example.com',
      ),
      throwsA(
        isA<RecordingUploadException>().having(
          (error) => error.message,
          'message',
          contains('do not belong'),
        ),
      ),
    );
    expect(requestWasSent, isFalse);
  });

  test(
    'uses finalized audio duration when stored call duration is zero',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'recording-upload-duration-test-',
      );
      final recording = File('${tempDirectory.path}/sample.aac');
      await recording.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() => tempDirectory.delete(recursive: true));

      late http.Request capturedRequest;
      final uploader = HttpRecordingUploader(
        endpoint: Uri.parse('https://example.test/api/recordings'),
        credentialProvider: _TestCredentialManager(),
        fileInspector: const _ReadyRecordingInspector(durationSeconds: 23),
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            '{"ok":true,"call_log":{"id":123}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await uploader.upload(
        call: CallModel(
          sessionId: 'call-zero-duration',
          phoneNumber: '0755962582',
          callType: 'outgoing',
          duration: 0,
          audioPath: recording.path,
          status: 'pending',
          createdAt: '2026-07-24T13:00:20.000',
        ),
        customerId: 'CUST-001',
        agentEmail: 'agent@example.com',
      );

      expect(capturedRequest.body, contains('name="duration_seconds"'));
      expect(capturedRequest.body, contains('\r\n\r\n23\r\n'));
      expect(capturedRequest.body, contains('content-type: audio/aac'));
    },
  );

  test('does not send an empty or unfinished recording', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-upload-empty-test-',
    );
    final recording = File('${tempDirectory.path}/empty.m4a');
    await recording.writeAsBytes(const []);
    addTearDown(() => tempDirectory.delete(recursive: true));

    var requestWasSent = false;
    final uploader = HttpRecordingUploader(
      endpoint: Uri.parse('https://example.test/api/recordings'),
      credentialProvider: _TestCredentialManager(),
      fileInspector: const _UnreadyRecordingInspector(),
      client: MockClient((request) async {
        requestWasSent = true;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      uploader.upload(
        call: CallModel(
          sessionId: 'call-empty',
          phoneNumber: '0755962582',
          callType: 'outgoing',
          duration: 0,
          audioPath: recording.path,
          status: 'pending',
          createdAt: '2026-07-24T13:00:20.000',
        ),
        customerId: 'CUST-001',
        agentEmail: 'agent@example.com',
      ),
      throwsA(
        isA<RecordingUploadException>().having(
          (error) => error.message,
          'message',
          contains('empty or still being finalized'),
        ),
      ),
    );
    expect(requestWasSent, isFalse);
  });

  test('does not upload an app microphone recording', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-upload-mic-test-',
    );
    final recording = File(
      '${tempDirectory.path}/app_flutter/recordings/call.m4a',
    );
    await recording.parent.create(recursive: true);
    await recording.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    var requestWasSent = false;
    final uploader = HttpRecordingUploader(
      endpoint: Uri.parse('https://example.test/api/recordings'),
      credentialProvider: _TestCredentialManager(),
      fileInspector: const _ReadyRecordingInspector(),
      client: MockClient((request) async {
        requestWasSent = true;
        return http.Response('{}', 500);
      }),
    );

    await expectLater(
      uploader.upload(
        call: CallModel(
          sessionId: 'call-app-mic',
          phoneNumber: '0755962582',
          callType: 'outgoing',
          duration: 10,
          audioPath: recording.path,
          status: 'pending',
          createdAt: '2026-07-24T13:00:20.000',
        ),
        customerId: 'CUST-001',
        agentEmail: 'agent@example.com',
      ),
      throwsA(
        isA<RecordingUploadException>().having(
          (error) => error.message,
          'message',
          contains('not the phone dialer recording'),
        ),
      ),
    );
    expect(requestWasSent, isFalse);
  });

  test('device inspector requires a non-empty stable file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-readiness-test-',
    );
    final recording = File('${tempDirectory.path}/sample.m4a');
    await recording.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    final inspector = DeviceRecordingFileInspector(
      maxAttempts: 2,
      retryDelay: Duration.zero,
      durationReader: (_) async => 22500,
    );

    final readiness = await inspector.waitUntilReady(recording.path);
    expect(readiness?.sizeBytes, 4);
    expect(readiness?.durationSeconds, 23);
  });

  test('device inspector rejects a zero-byte file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'recording-empty-readiness-test-',
    );
    final recording = File('${tempDirectory.path}/empty.aac');
    await recording.writeAsBytes(const []);
    addTearDown(() => tempDirectory.delete(recursive: true));

    var durationWasRead = false;
    final inspector = DeviceRecordingFileInspector(
      maxAttempts: 2,
      retryDelay: Duration.zero,
      durationReader: (_) async {
        durationWasRead = true;
        return 1000;
      },
    );

    expect(await inspector.waitUntilReady(recording.path), isNull);
    expect(durationWasRead, isFalse);
  });
}

class _ReadyRecordingInspector implements RecordingFileInspector {
  final int durationSeconds;

  const _ReadyRecordingInspector({this.durationSeconds = 17});

  @override
  Future<RecordingFileReadiness?> waitUntilReady(String filePath) async {
    return RecordingFileReadiness(
      sizeBytes: 4,
      durationSeconds: durationSeconds,
    );
  }
}

class _UnreadyRecordingInspector implements RecordingFileInspector {
  const _UnreadyRecordingInspector();

  @override
  Future<RecordingFileReadiness?> waitUntilReady(String filePath) async => null;
}

class _TestCredentialManager implements AgentCredentialManager {
  _TestCredentialManager({
    this.saved = const ApiCredentials(
      email: 'agent@example.com',
      apiKey: 'test-api-key',
      apiSecret: 'test-api-secret',
    ),
    this.activated = const ApiCredentials(
      email: 'agent@example.com',
      apiKey: 'test-api-key',
      apiSecret: 'test-api-secret',
    ),
  });

  final ApiCredentials? saved;
  final ApiCredentials activated;

  @override
  Future<ApiCredentials?> read() async {
    return saved;
  }

  @override
  Future<ApiCredentials> activateForEmail(String email) async {
    return activated;
  }

  @override
  Future<void> clear() async {}
}
