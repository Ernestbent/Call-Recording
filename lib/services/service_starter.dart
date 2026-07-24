import 'package:calls_recording/models/call_recording_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ServiceStarter {
  static const platform = MethodChannel('call_recorder_service');
  static void Function(String filePath)? _onPlaybackCompleted;
  static void Function(String filePath)? _onPlaybackFailed;

  static void configurePlaybackEvents({
    required void Function(String filePath) onCompleted,
    required void Function(String filePath) onFailed,
  }) {
    _onPlaybackCompleted = onCompleted;
    _onPlaybackFailed = onFailed;
    platform.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      final filePath = arguments is Map
          ? arguments['filePath']?.toString()
          : null;
      if (filePath == null) return;

      switch (call.method) {
        case 'playbackCompleted':
          _onPlaybackCompleted?.call(filePath);
        case 'playbackFailed':
          _onPlaybackFailed?.call(filePath);
      }
    });
  }

  static Future<void> startService() async {
    try {
      await platform.invokeMethod('startService');
    } catch (e) {
      debugPrint('Failed to start service: $e');
    }
  }

  static Future<void> stopService() async {
    try {
      await platform.invokeMethod('stopService');
    } catch (e) {
      debugPrint('Failed to stop service: $e');
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
      debugPrint('Failed to find recent call recording: $e');
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
      debugPrint('Failed to find recordings for phone: $e');
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
      debugPrint('Failed to open dialer: $e');
      return false;
    }
  }

  static Future<bool> playRecording(String filePath) async {
    try {
      final didStart = await platform.invokeMethod<bool>('playRecording', {
        'filePath': filePath,
      });
      return didStart ?? false;
    } catch (e) {
      debugPrint('Failed to play recording: $e');
      return false;
    }
  }

  static Future<bool> pauseRecording() async {
    try {
      return await platform.invokeMethod<bool>('pauseRecording') ?? false;
    } catch (e) {
      debugPrint('Failed to pause recording: $e');
      return false;
    }
  }

  static Future<bool> resumeRecording() async {
    try {
      return await platform.invokeMethod<bool>('resumeRecording') ?? false;
    } catch (e) {
      debugPrint('Failed to resume recording: $e');
      return false;
    }
  }
}
