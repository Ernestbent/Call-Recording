import 'package:calls_recording/services/call_manager.dart';
import 'package:calls_recording/services/session_manager.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:phone_state/phone_state.dart';

class CallController {
  final CallManager callManager;
  final SessionManager sessionManager;

  CallController({
    required this.callManager,
    required this.sessionManager,
  });

  // Start everything
  Future<void> init() async {
    print('\n════════════════════════════════════════════════════');
    print('🚀 INITIALIZING CALL CONTROLLER');
    print('════════════════════════════════════════════════════\n');

    // Request permissions
    print('Step 1: Requesting permissions...');
    final granted = await callManager.requestPermissions();

    if (!granted) {
      print('\n❌ PERMISSIONS DENIED - Cannot continue!');
      print('════════════════════════════════════════════════════\n');
      return;
    }

    // Start listening
    print('\nStep 2: Starting phone state listener...');
    callManager.startListening((PhoneState event) {
      _handleCallEvent(event);
    });

    print('\n✅ CALL CONTROLLER INITIALIZED SUCCESSFULLY');
    print('════════════════════════════════════════════════════');
    print('⏳ Waiting for phone calls...\n');
  }

  // Handle call events
  void _handleCallEvent(PhoneState event) {
    final status = event.status;
    final number = event.number ?? 'Unknown';

    print('\n⚡ HANDLING CALL EVENT');
    print('   Status Type: $status');
    print('   Phone Number: $number');

    // Call started (incoming or outgoing)
    if (status == PhoneStateStatus.CALL_STARTED) {
      print('\n🔴 ▶️ CALL STARTED!');
      print('   → Phone number: $number');

      try {
        print('   → Notifying SessionManager...');
        sessionManager.onCallStart(number);
        print('   ✅ SessionManager notified');

        print('   → Starting Android recording service...');
        ServiceStarter.startService();
        print('   ✅ Recording service started');
      } catch (e) {
        print('   ❌ Error: $e');
      }
    }

    // Call ended
    else if (status == PhoneStateStatus.CALL_ENDED) {
      print('\n🟢 ⏹️ CALL ENDED!');
      print('   → Phone number: $number');

      try {
        print('   → Notifying SessionManager...');
        sessionManager.onCallEnd();
        print('   ✅ SessionManager notified');
      } catch (e) {
        print('   ❌ Error: $e');
      }
    }

    else {
      print('\n❓ OTHER STATE: $status');
    }

    print('');
  }

  // Stop listening
  void dispose() {
    print('\n🛑 Disposing CallController...');
    callManager.stopListening();
    print('✅ CallController disposed\n');
  }
}