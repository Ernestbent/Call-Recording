import 'dart:convert';

import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('activates only the credentials matching the signed-in email', () async {
    final storage = _MemoryCredentialValueStorage();
    final manager = SecureAgentCredentialManager(
      assetBundle: _StringAssetBundle(
        jsonEncode([
          {
            'email': 'first@example.com',
            'api_key': 'first-key',
            'api_secret': 'first-secret',
          },
          {
            'email': 'Agent@Example.com',
            'api_key': 'matching-key',
            'api_secret': 'matching-secret',
          },
        ]),
      ),
      storage: storage,
    );

    final credentials = await manager.activateForEmail(' agent@example.com ');
    final persistedCredentials = await manager.read();

    expect(credentials.email, 'Agent@Example.com');
    expect(credentials.apiKey, 'matching-key');
    expect(persistedCredentials?.belongsTo('agent@example.com'), isTrue);
    expect(storage.values.length, 1);
  });

  test('rejects an account missing from the credential catalog', () async {
    final storage = _MemoryCredentialValueStorage();
    final manager = SecureAgentCredentialManager(
      assetBundle: _StringAssetBundle(
        jsonEncode([
          {
            'email': 'other@example.com',
            'api_key': 'other-key',
            'api_secret': 'other-secret',
          },
        ]),
      ),
      storage: storage,
    );

    expect(
      () => manager.activateForEmail('missing@example.com'),
      throwsA(isA<AgentCredentialException>()),
    );
    expect(storage.values, isEmpty);
  });
}

class _StringAssetBundle extends CachingAssetBundle {
  final String contents;

  _StringAssetBundle(this.contents);

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(contents));
    return ByteData.sublistView(bytes);
  }
}

class _MemoryCredentialValueStorage implements CredentialValueStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
