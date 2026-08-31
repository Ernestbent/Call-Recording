import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';

class CallManager {
  StreamSubscription<PhoneState>? _subscription;
  DateTime? _lastEventTime;

  // Request permissions needed for call detection
  Future<bool> requestPermissions() async {
    try {
      debugPrint('📱 Requesting Phone permission...');
      final phoneStatus = await Permission.phone.request();
      debugPrint(
        '   Phone: ${phoneStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}',
      );

      if (Platform.isAndroid) {
        debugPrint('📱 Requesting Notification permission...');
        final notificationStatus = await Permission.notification.request();
        debugPrint(
          '   Notifications: ${notificationStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}',
        );
      }

      debugPrint('📱 Requesting Storage permission...');
      final storageStatus = await Permission.storage.request();
      debugPrint(
        '   Storage: ${storageStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}',
      );

      debugPrint('📱 Requesting Audio files permission...');
      final audioStatus = await Permission.audio.request();
      debugPrint(
        '   Audio files: ${audioStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}',
      );

      PermissionStatus? manageStorageStatus;
      if (Platform.isAndroid) {
        debugPrint('📱 Requesting All files access...');
        manageStorageStatus = await Permission.manageExternalStorage.request();
        debugPrint(
          '   All files: ${manageStorageStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}',
        );
      }

      final hasRecordingFileAccess =
          storageStatus.isGranted ||
          audioStatus.isGranted ||
          (manageStorageStatus?.isGranted ?? false);
      final allGranted = phoneStatus.isGranted && hasRecordingFileAccess;

      debugPrint(
        allGranted ? '✅ All permissions granted' : '❌ Some permissions denied',
      );

      return allGranted;
    } catch (e) {
      debugPrint('❌ Permission error: $e');
      return false;
    }
  }

  // Start listening to call state changes
  void startListening(Function(PhoneState status) onEvent) {
    try {
      debugPrint('👂 Starting to listen for phone state changes...');
      debugPrint('   (Waiting for CALL_STARTED and CALL_ENDED events)\n');

      _subscription = PhoneState.stream.listen(
        (event) {
          final now = DateTime.now();
          final timeSinceLastEvent = _lastEventTime != null
              ? now.difference(_lastEventTime!).inSeconds
              : 0;
          _lastEventTime = now;

          debugPrint('\n═════════════════════════════════════════');
          debugPrint('📞 CALL EVENT DETECTED!');
          debugPrint('═════════════════════════════════════════');
          debugPrint('Status: ${event.status}');
          debugPrint('Number: ${event.number ?? "Unknown"}');
          debugPrint('Time: $now');
          debugPrint('Seconds since last event: $timeSinceLastEvent sec');
          debugPrint('═════════════════════════════════════════\n');

          // Debug: Print the actual enum value
          if (event.status == PhoneStateStatus.CALL_STARTED) {
            debugPrint('✅ Detected as CALL_STARTED');
          } else if (event.status == PhoneStateStatus.CALL_ENDED) {
            debugPrint('✅ Detected as CALL_ENDED');
          } else {
            debugPrint('❓ Detected as: ${event.status.runtimeType}');
          }

          onEvent(event); // Pass to callback
        },
        onError: (error, stackTrace) {
          debugPrint('\n❌ STREAM ERROR!');
          debugPrint('Error: $error');
          debugPrint('StackTrace: $stackTrace');
        },
        onDone: () {
          debugPrint('\n⚠️ STREAM CLOSED!');
          debugPrint('Phone state stream has ended unexpectedly');
          _subscription = null;
        },
        cancelOnError: false,
      );

      debugPrint('✅ Phone state listener started successfully');
      debugPrint('⏳ Listening for events... Keep app in foreground!\n');
    } catch (e) {
      debugPrint('❌ Error starting listener: $e');
    }
  }

  // Stop listening
  void stopListening() {
    try {
      if (_subscription != null) {
        _subscription?.cancel();
        _subscription = null;
        debugPrint('🛑 Phone state listener stopped');
      }
    } catch (e) {
      debugPrint('❌ Error stopping listener: $e');
    }
  }

  // Check if listening
  bool get isListening => _subscription != null;
}
