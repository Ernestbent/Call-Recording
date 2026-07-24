import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists and reads the recording API endpoint', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = RecordingUploadSettings();

    expect(await settings.readEndpoint(), isNull);

    await settings.saveEndpoint(
      'https://example.ngrok-free.dev/api/recordings',
    );

    expect(
      await settings.readEndpoint(),
      Uri.parse('https://example.ngrok-free.dev/api/recordings'),
    );
  });

  test('rejects invalid recording API endpoints', () {
    expect(RecordingUploadSettings.parseEndpoint('not-a-url'), isNull);
    expect(RecordingUploadSettings.parseEndpoint('ftp://example.com'), isNull);
    expect(
      RecordingUploadSettings.parseEndpoint(
        'https://example.com/api/recordings',
      ),
      Uri.parse('https://example.com/api/recordings'),
    );
  });
}
