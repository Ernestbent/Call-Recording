import 'dart:io';

import 'package:calls_recording/db/call_model.dart';
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
        bearerToken: 'test-token',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            '{"success":true,"upload_id":"upload-123",'
            '"message":"Recording uploaded"}',
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

      final result = await uploader.upload(call: call, customerId: 'CUST-001');

      expect(result.uploadId, 'upload-123');
      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url,
        Uri.parse('https://example.test/api/recordings'),
      );
      expect(capturedRequest.headers['authorization'], 'Bearer test-token');
      expect(
        capturedRequest.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(capturedRequest.body, contains('name="recording"'));
      expect(capturedRequest.body, contains('filename="sample.mp3"'));
      expect(capturedRequest.body, contains('name="session_id"'));
      expect(capturedRequest.body, contains('call-123'));
      expect(capturedRequest.body, contains('name="phone_number"'));
      expect(capturedRequest.body, contains('0755962582'));
      expect(capturedRequest.body, contains('name="customer_id"'));
      expect(capturedRequest.body, contains('CUST-001'));
    },
  );
}
