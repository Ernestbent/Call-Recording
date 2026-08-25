import 'package:calls_recording/models/call_recording_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the PhoneRecord timestamp format from an AAC filename', () {
    final recording = CallRecordingFile(
      filePath:
          '/storage/emulated/0/Music/PhoneRecord/0757001909/'
          '2026-08-20_10.51.00.aac',
      fileName: '2026-08-20_10.51.00.aac',
      lastModifiedTime: DateTime(2026, 8, 20, 11),
    );

    expect(recording.fileNameTimestamp, DateTime(2026, 8, 20, 10, 51));
    expect(recording.effectiveTimestamp, DateTime(2026, 8, 20, 10, 51));
  });
}
