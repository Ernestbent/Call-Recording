import 'dart:math';

import 'package:calls_recording/services/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves only a salted pattern hash and verifies the pattern', () async {
    final storage = _MemoryAppLockStorage();
    final service = AppLockService(storage: storage, secureRandom: Random(7));

    await service.savePattern([0, 1, 4, 7]);

    final configuration = await service.readConfiguration();
    expect(configuration.enabled, isTrue);
    expect(configuration.patternConfigured, isTrue);
    expect(configuration.biometricsEnabled, isFalse);
    expect(storage.values['pattern_hash'], isNot('0-1-4-7'));
    expect(storage.values['pattern_salt'], isNotEmpty);
    expect(await service.verifyPattern([0, 1, 4, 7]), isTrue);
    expect(await service.verifyPattern([0, 1, 4, 8]), isFalse);
  });

  test(
    'disabling app lock removes its pattern and biometric setting',
    () async {
      final storage = _MemoryAppLockStorage();
      final service = AppLockService(
        storage: storage,
        secureRandom: Random(11),
      );
      await service.savePattern([0, 3, 6, 7]);
      await service.setBiometricsEnabled(true);

      await service.disable();

      expect(await service.readConfiguration(), _isDisabled);
      expect(storage.values.containsKey('pattern_hash'), isFalse);
      expect(storage.values.containsKey('pattern_salt'), isFalse);
    },
  );

  test('rejects patterns with fewer than four dots', () async {
    final service = AppLockService(
      storage: _MemoryAppLockStorage(),
      secureRandom: Random(3),
    );

    await expectLater(service.savePattern([0, 1, 2]), throwsArgumentError);
  });
}

final _isDisabled = isA<AppLockConfiguration>()
    .having((value) => value.enabled, 'enabled', isFalse)
    .having((value) => value.patternConfigured, 'patternConfigured', isFalse)
    .having((value) => value.biometricsEnabled, 'biometricsEnabled', isFalse);

class _MemoryAppLockStorage implements AppLockStorage {
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
