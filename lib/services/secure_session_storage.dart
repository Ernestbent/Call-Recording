import 'dart:convert';

import 'package:calls_recording/models/erpnext_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStorage {
  Future<void> save(ErpNextSession session);

  Future<ErpNextSession?> read();

  Future<void> clear();
}

class SecureSessionStorage implements SessionStorage {
  static const _sessionKey = 'erpnext_session';

  final FlutterSecureStorage _storage;

  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'erpnext_auth'),
          );

  @override
  Future<void> save(ErpNextSession session) {
    return _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  @override
  Future<ErpNextSession?> read() async {
    final encodedSession = await _storage.read(key: _sessionKey);
    if (encodedSession == null) return null;

    try {
      final decodedSession = jsonDecode(encodedSession);
      if (decodedSession is! Map<String, dynamic>) {
        await clear();
        return null;
      }
      return ErpNextSession.fromJson(decodedSession);
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _sessionKey);
  }
}
