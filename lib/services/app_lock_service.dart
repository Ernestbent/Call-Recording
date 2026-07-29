import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockConfiguration {
  final bool enabled;
  final bool patternConfigured;
  final bool biometricsEnabled;

  const AppLockConfiguration({
    required this.enabled,
    required this.patternConfigured,
    required this.biometricsEnabled,
  });

  static const disabled = AppLockConfiguration(
    enabled: false,
    patternConfigured: false,
    biometricsEnabled: false,
  );
}

abstract interface class AppLockStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureAppLockStorage implements AppLockStorage {
  final FlutterSecureStorage _storage;

  SecureAppLockStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'calls_app_lock'),
          );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppLockService {
  static const _enabledKey = 'enabled';
  static const _biometricsEnabledKey = 'biometrics_enabled';
  static const _patternHashKey = 'pattern_hash';
  static const _patternSaltKey = 'pattern_salt';

  final AppLockStorage _storage;
  final LocalAuthentication _localAuthentication;
  final Random _secureRandom;

  AppLockService({
    AppLockStorage? storage,
    LocalAuthentication? localAuthentication,
    Random? secureRandom,
  }) : _storage = storage ?? SecureAppLockStorage(),
       _localAuthentication = localAuthentication ?? LocalAuthentication(),
       _secureRandom = secureRandom ?? Random.secure();

  Future<AppLockConfiguration> readConfiguration() async {
    try {
      final values = await Future.wait([
        _storage.read(_enabledKey),
        _storage.read(_biometricsEnabledKey),
        _storage.read(_patternHashKey),
        _storage.read(_patternSaltKey),
      ]);
      final patternConfigured =
          values[2]?.isNotEmpty == true && values[3]?.isNotEmpty == true;
      final enabled = values[0] == 'true' && patternConfigured;

      return AppLockConfiguration(
        enabled: enabled,
        patternConfigured: patternConfigured,
        biometricsEnabled: enabled && values[1] == 'true',
      );
    } catch (_) {
      // Secure storage is not available on every Flutter target. The main
      // Android/iOS app remains usable instead of being permanently locked.
      return AppLockConfiguration.disabled;
    }
  }

  Future<void> savePattern(List<int> pattern) async {
    _validatePattern(pattern);
    final salt = List<int>.generate(24, (_) => _secureRandom.nextInt(256));
    final encodedSalt = base64UrlEncode(salt);
    final patternHash = _hashPattern(pattern, salt);

    await _storage.write(_patternSaltKey, encodedSalt);
    await _storage.write(_patternHashKey, patternHash);
    await _storage.write(_enabledKey, 'true');
  }

  Future<bool> verifyPattern(List<int> pattern) async {
    if (pattern.isEmpty) return false;

    try {
      final values = await Future.wait([
        _storage.read(_patternHashKey),
        _storage.read(_patternSaltKey),
      ]);
      final savedHash = values[0];
      final encodedSalt = values[1];
      if (savedHash == null || encodedSalt == null) return false;

      final candidateHash = _hashPattern(
        pattern,
        base64Url.decode(encodedSalt),
      );
      return _constantTimeEquals(savedHash, candidateHash);
    } catch (_) {
      return false;
    }
  }

  Future<void> disable() async {
    await _storage.write(_enabledKey, 'false');
    await _storage.write(_biometricsEnabledKey, 'false');
    await _storage.delete(_patternHashKey);
    await _storage.delete(_patternSaltKey);
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(_biometricsEnabledKey, enabled ? 'true' : 'false');
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      if (!await _localAuthentication.canCheckBiometrics) {
        return const [];
      }
      return await _localAuthentication.getAvailableBiometrics();
    } on PlatformException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      if ((await availableBiometrics()).isEmpty) return false;

      return await _localAuthentication.authenticate(
        localizedReason: 'Authenticate to unlock Calls Recording',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _validatePattern(List<int> pattern) {
    if (pattern.length < 4 || pattern.toSet().length != pattern.length) {
      throw ArgumentError('A pattern must connect at least four unique dots.');
    }
    if (pattern.any((dot) => dot < 0 || dot > 8)) {
      throw ArgumentError('Pattern dots must be between 0 and 8.');
    }
  }

  String _hashPattern(List<int> pattern, List<int> salt) {
    final value = utf8.encode(pattern.join('-'));
    return sha256.convert([...salt, ...value]).toString();
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;

    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
