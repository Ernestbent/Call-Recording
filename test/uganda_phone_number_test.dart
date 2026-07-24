import 'package:calls_recording/utils/uganda_phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds the Uganda trunk prefix to mobile numbers beginning with 7', () {
    expect(UgandaPhoneNumber.normalize('755962582'), '0755962582');
  });

  test('converts Uganda international mobile numbers to local format', () {
    expect(UgandaPhoneNumber.normalize('256755962582'), '0755962582');
    expect(UgandaPhoneNumber.normalize('+256 755 962 582'), '0755962582');
    expect(UgandaPhoneNumber.normalize('00256755962582'), '0755962582');
  });

  test('keeps correctly formatted and unrelated numbers unchanged', () {
    expect(UgandaPhoneNumber.normalize('0755962582'), '0755962582');
    expect(UgandaPhoneNumber.normalize('0414123456'), '0414123456');
  });
}
