import 'package:local_auth/local_auth.dart';

abstract interface class BiometricAuthenticator {
  Future<bool> authenticate();
}

class BiometricAuthException implements Exception {
  final String message;

  const BiometricAuthException(this.message);

  @override
  String toString() => message;
}

class BiometricAuthService implements BiometricAuthenticator {
  final LocalAuthentication _localAuthentication;

  BiometricAuthService({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  @override
  Future<bool> authenticate() async {
    try {
      final availableBiometrics = await _localAuthentication
          .getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        throw const BiometricAuthException(
          'No fingerprint is enrolled. Add one in your phone settings first.',
        );
      }

      return _localAuthentication.authenticate(
        localizedReason: 'Scan your fingerprint to open Call Recorder',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on BiometricAuthException {
      rethrow;
    } on LocalAuthException {
      throw const BiometricAuthException(
        'Fingerprint login is unavailable or temporarily locked.',
      );
    } catch (_) {
      throw const BiometricAuthException(
        'Fingerprint login is not available on this device.',
      );
    }
  }
}
