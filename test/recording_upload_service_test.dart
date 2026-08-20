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
  });
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
