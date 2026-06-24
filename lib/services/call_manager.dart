import 'dart:async';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';

class CallManager {
  StreamSubscription<PhoneState>? _subscription;
  DateTime? _lastEventTime;

  // Request permissions needed for call detection
  Future<bool> requestPermissions() async {
    try {
      print('📱 Requesting Phone permission...');
      final phoneStatus = await Permission.phone.request();
      print('   Phone: ${phoneStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}');

      print('📱 Requesting Microphone permission...');
      final micStatus = await Permission.microphone.request();
      print('   Mic: ${micStatus.isGranted ? "✅ GRANTED" : "❌ DENIED"}');

      final allGranted = phoneStatus.isGranted && micStatus.isGranted;
      
      print(allGranted
          ? '✅ All permissions granted'
          : '❌ Some permissions denied');

      return allGranted;
    } catch (e) {
      print('❌ Permission error: $e');
      return false;
    }
  }

  // Start listening to call state changes
  void startListening(Function(PhoneState status) onEvent) {
    try {
      print('👂 Starting to listen for phone state changes...');
      print('   (Waiting for CALL_STARTED and CALL_ENDED events)\n');

      _subscription = PhoneState.stream.listen(
        (event) {
          final now = DateTime.now();
          final timeSinceLastEvent = _lastEventTime != null 
              ? now.difference(_lastEventTime!).inSeconds 
              : 0;
          _lastEventTime = now;

          print('\n═════════════════════════════════════════');
          print('📞 CALL EVENT DETECTED!');
          print('═════════════════════════════════════════');
          print('Status: ${event.status}');
          print('Number: ${event.number ?? "Unknown"}');
          print('Time: $now');
          print('Seconds since last event: $timeSinceLastEvent sec');
          print('═════════════════════════════════════════\n');

          // Debug: Print the actual enum value
          if (event.status == PhoneStateStatus.CALL_STARTED) {
            print('✅ Detected as CALL_STARTED');
          } else if (event.status == PhoneStateStatus.CALL_ENDED) {
            print('✅ Detected as CALL_ENDED');
          } else {
            print('❓ Detected as: ${event.status.runtimeType}');
          }

          onEvent(event); // Pass to callback
        },
        onError: (error, stackTrace) {
          print('\n❌ STREAM ERROR!');
          print('Error: $error');
          print('StackTrace: $stackTrace');
        },
        onDone: () {
          print('\n⚠️ STREAM CLOSED!');
          print('Phone state stream has ended unexpectedly');
          _subscription = null;
        },
        cancelOnError: false,
      );

      print('✅ Phone state listener started successfully');
      print('⏳ Listening for events... Keep app in foreground!\n');
    } catch (e) {
      print('❌ Error starting listener: $e');
    }
  }

  // Stop listening
  void stopListening() {
    try {
      if (_subscription != null) {
        _subscription?.cancel();
        _subscription = null;
        print('🛑 Phone state listener stopped');
      }
    } catch (e) {
      print('❌ Error stopping listener: $e');
    }
  }

  // Check if listening
  bool get isListening => _subscription != null;
}