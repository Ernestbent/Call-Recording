import 'dart:convert';

import 'package:calls_recording/models/api_credentials.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ApiCredentialProvider {
  Future<ApiCredentials?> read();
}

abstract interface class AgentCredentialManager
    implements ApiCredentialProvider {
  Future<ApiCredentials> activateForEmail(String email);

  Future<void> clear();
}

abstract interface class CredentialValueStorage {
  Future<void> write(String key, String value);

  Future<String?> read(String key);

  Future<void> delete(String key);
}

class FlutterCredentialValueStorage implements CredentialValueStorage {
  final FlutterSecureStorage _storage;

  FlutterCredentialValueStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'erpnext_mobile_auth'),
          );

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}

class AgentCredentialException implements Exception {
  final String message;

  const AgentCredentialException(this.message);

  @override
  String toString() => message;
}

class SecureAgentCredentialManager implements AgentCredentialManager {
  static const String _assetPath = 'assets/agent_credentials.json';
  static const String _activeCredentialsKey = 'active_erpnext_api_credentials';
  static const String _localTestEmail = String.fromEnvironment(
    'LOCAL_TEST_AGENT_EMAIL',
  );
  static const String _localTestApiKey = String.fromEnvironment(
    'LOCAL_TEST_API_KEY',
  );
  static const String _localTestApiSecret = String.fromEnvironment(
    'LOCAL_TEST_API_SECRET',
  );

  final AssetBundle _assetBundle;
  final CredentialValueStorage _storage;

  SecureAgentCredentialManager({
    AssetBundle? assetBundle,
    CredentialValueStorage? storage,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _storage = storage ?? FlutterCredentialValueStorage();

  @override
  Future<ApiCredentials> activateForEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw const AgentCredentialException(
        'ERPNext did not identify the signed-in user.',
      );
    }

    try {
      final localTestCredentials = ApiCredentials(
        email: _localTestEmail,
        apiKey: _localTestApiKey,
        apiSecret: _localTestApiSecret,
      );
      if (localTestCredentials.isComplete &&
          localTestCredentials.belongsTo(normalizedEmail)) {
        await _storage.write(
          _activeCredentialsKey,
          jsonEncode(localTestCredentials.toJson()),
        );
        return localTestCredentials;
      }

      final encodedCatalog = await _assetBundle.loadString(_assetPath);
      final decodedCatalog = jsonDecode(encodedCatalog);
      final entries = _catalogEntries(decodedCatalog);
      final matches = entries
          .where((entry) {
            return entry.email.toLowerCase() == normalizedEmail;
          })
          .toList(growable: false);

      if (matches.isEmpty) {
        throw AgentCredentialException(
          'No upload credentials are configured for $email.',
        );
      }
      if (matches.length > 1) {
        throw AgentCredentialException(
          'Duplicate upload credentials are configured for $email.',
        );
      }

      final credentials = matches.single;
      if (!credentials.isComplete) {
        throw AgentCredentialException(
          'Upload credentials for $email are incomplete.',
        );
      }

      await _storage.write(
        _activeCredentialsKey,
        jsonEncode(credentials.toJson()),
      );
      return credentials;
    } on AgentCredentialException {
      await _bestEffortClear();
      rethrow;
    } on FormatException {
      await _bestEffortClear();
      throw const AgentCredentialException(
        'The bundled agent credential file is invalid.',
      );
    } on FlutterError {
      await _bestEffortClear();
      throw const AgentCredentialException(
        'The bundled agent credential file is missing.',
      );
    } on PlatformException {
      await _bestEffortClear();
      throw const AgentCredentialException(
        'Secure credential storage is unavailable on this device.',
      );
    } catch (_) {
      await _bestEffortClear();
      throw const AgentCredentialException(
        'Could not prepare upload credentials for this account.',
      );
    }
  }

  @override
  Future<ApiCredentials?> read() async {
    try {
      final encodedCredentials = await _storage.read(_activeCredentialsKey);
      if (encodedCredentials == null) return null;

      final decodedCredentials = jsonDecode(encodedCredentials);
      if (decodedCredentials is! Map) {
        await clear();
        return null;
      }

      final credentials = ApiCredentials.fromJson(
        Map<String, dynamic>.from(decodedCredentials),
      );
      if (!credentials.isComplete) {
        await clear();
        return null;
      }
      return credentials;
    } catch (_) {
      await _bestEffortClear();
      return null;
    }
  }

  @override
  Future<void> clear() {
    return _storage.delete(_activeCredentialsKey);
  }

  Future<void> _bestEffortClear() async {
    try {
      await clear();
    } catch (_) {
      // Preserve the original, non-sensitive setup error.
    }
  }

  List<ApiCredentials> _catalogEntries(Object? decodedCatalog) {
    final Object? rawEntries;
    if (decodedCatalog is List) {
      rawEntries = decodedCatalog;
    } else if (decodedCatalog is Map) {
      rawEntries = decodedCatalog['agents'];
    } else {
      rawEntries = null;
    }

    if (rawEntries is! List) {
      throw const FormatException('Expected an agent credential list.');
    }

    return rawEntries
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException('Invalid agent credential entry.');
          }
          return ApiCredentials.fromJson(Map<String, dynamic>.from(entry));
        })
        .toList(growable: false);
  }
}
