import 'package:calls_recording/models/call_recording_file.dart';
import 'package:flutter/services.dart';

class ServiceStarter {
  static const platform = MethodChannel('call_recorder_service');

  static Future<void> startService() async {
    try {
      await platform.invokeMethod('startService');
    } catch (e) {
      print("Failed to start service: $e");
    }
  }

  static Future<void> stopService() async {
    try {
      await platform.invokeMethod('stopService');
    } catch (e) {
      print("Failed to stop service: $e");
    }
  }

  static Future<CallRecordingFile?> findRecentCallRecording({
    required String phoneNumber,
    required DateTime callEndTime,
    int windowSeconds = 60,
  }) async {
    try {
      final result = await platform
          .invokeMapMethod<String, dynamic>('findRecentCallRecording', {
            'phoneNumber': phoneNumber,
            'callEndTimeMillis': callEndTime.millisecondsSinceEpoch,
            'windowSeconds': windowSeconds,
          });

      if (result == null) return null;
      return CallRecordingFile.fromMap(result);
    } catch (e) {
      print("Failed to find recent call recording: $e");
      return null;
    }
  }

  static Future<List<CallRecordingFile>> findRecordingsForPhone(
    String phoneNumber,
  ) async {
    try {
      final result = await platform.invokeListMethod<dynamic>(
        'findRecordingsForPhone',
        {'phoneNumber': phoneNumber},
      );

      if (result == null) return const [];
      return result
          .map(
            (item) => CallRecordingFile.fromMap(item as Map<dynamic, dynamic>),
          )
          .toList();
    } catch (e) {
      print("Failed to find recordings for phone: $e");
      return const [];
    }
  }

  static Future<bool> openDialer(String phoneNumber) async {
    try {
      final result = await platform.invokeMethod<bool>('openDialer', {
        'phoneNumber': phoneNumber,
      });
      return result ?? false;
    } catch (e) {
      print("Failed to open dialer: $e");
      return false;
    }
  }

  static Future<void> playRecording(String filePath) async {
    try {
      await platform.invokeMethod('playRecording', {'filePath': filePath});
    } catch (e) {
      print("Failed to play recording: $e");
    }
  }
}
