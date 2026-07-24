import 'dart:convert';

import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login sends credentials to ERPNext and reads the sid cookie', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://accounting.autozonepro.org/api/method/login'),
      );
      expect(jsonDecode(request.body), {
        'usr': 'agent@example.com',
        'pwd': 'test-password',
      });

      return http.Response(
        jsonEncode({'message': 'Logged In', 'full_name': 'Test Agent'}),
        200,
        headers: {
          'set-cookie':
              'full_name=Test%20Agent; Path=/, '
              'sid=test-session-id; HttpOnly; Path=/',
        },
      );
    });
    final service = ErpNextAuthService(client: client);

    final session = await service.login(
      username: 'agent@example.com',
      password: 'test-password',
    );

    expect(session.sessionId, 'test-session-id');
    expect(session.userId, 'agent@example.com');
    expect(session.fullName, 'Test Agent');
  });

  test('login reports rejected ERPNext credentials', () async {
    final service = ErpNextAuthService(
      client: MockClient((_) async => http.Response('Not permitted', 401)),
    );

    expect(
      () => service.login(username: 'agent@example.com', password: 'wrong'),
      throwsA(
        isA<ErpNextAuthException>().having(
          (error) => error.message,
          'message',
          'Wrong username or password.',
        ),
      ),
    );
  });
}
