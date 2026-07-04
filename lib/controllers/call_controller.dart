import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/services/call_manager.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/session_manager.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:phone_state/phone_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallController {
  static const int _recordingLookupAttempts = 12;
  static const Duration _recordingLookupInitialDelay = Duration(seconds: 4);
  static const Duration _recordingLookupRetryDelay = Duration(seconds: 8);
  static const String _lastPhoneNumberKey = 'last_resolved_phone_number';
  static const String _lastCallStartedAtKey = 'last_call_started_at';

  final CallManager callManager;
  final SessionManager sessionManager;
  final CustomerCallStore customerCallStore;
  String? _lastResolvedPhoneNumber;
  DateTime? _lastCallStartedAt;

  CallController({
    required this.callManager,
    required this.sessionManager,
    required this.customerCallStore,
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
  Future<void> _handleCallEvent(PhoneState event) async {
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
        final callStartedAt = DateTime.now();
        final resolvedPhoneNumber =
            customerCallStore.phoneNumberForCurrentCall(event.number) ??
            event.number;

        _lastResolvedPhoneNumber = resolvedPhoneNumber;
        _lastCallStartedAt = callStartedAt;
        await _persistLastResolvedPhoneNumber(resolvedPhoneNumber);
        await _persistLastCallStartedAt(callStartedAt);

        print('   → Notifying SessionManager...');
        sessionManager.onCallStart(number);
        print('   ✅ SessionManager notified');

        customerCallStore.markCallStarted(
          resolvedPhoneNumber,
          startedAt: callStartedAt,
        );

        print('   → Starting Android recording service...');
        await ServiceStarter.startService();
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
        final callEndTime = DateTime.now();

        print('   → Notifying SessionManager...');
        sessionManager.onCallEnd();
        print('   ✅ SessionManager notified');

        final lookupPhoneNumber =
            customerCallStore.phoneNumberForCurrentCall(event.number) ??
            _lastResolvedPhoneNumber ??
            await _readPersistedPhoneNumber();
        final callStartedAt =
            _lastCallStartedAt ?? await _readPersistedCallStartedAt();

        if (lookupPhoneNumber == null || lookupPhoneNumber == 'Unknown') {
          print('   ⚠️ No resolved phone number available for recording lookup');
          return;
        }

        customerCallStore.markRecordingLookupStarted(
          phoneNumber: lookupPhoneNumber,
          callStartedAt: callStartedAt,
          callEndedAt: callEndTime,
        );

        print('   → Scheduling recording lookup...');
        _scheduleRecordingLookup(
          phoneNumber: lookupPhoneNumber,
          callStartedAt: callStartedAt,
          callEndTime: callEndTime,
        );
      } catch (e) {
        print('   ❌ Error: $e');
      }
    } else {
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

  void _scheduleRecordingLookup({
    required String phoneNumber,
    required DateTime? callStartedAt,
    required DateTime callEndTime,
  }) {
    Future<void>(() async {
      for (var attempt = 1; attempt <= _recordingLookupAttempts; attempt++) {
        if (attempt == 1) {
          await Future.delayed(_recordingLookupInitialDelay);
        } else {
          await Future.delayed(_recordingLookupRetryDelay);
        }

        final recording = await _findLatestPhoneRecording(
          attempt: attempt,
          phoneNumber: phoneNumber,
          callStartedAt: callStartedAt,
        );

        if (recording == null) {
          continue;
        }

        customerCallStore.markCallCompleted(
          phoneNumber: phoneNumber,
          callEndedAt: callEndTime,
          recording: recording,
        );

        _lastResolvedPhoneNumber = null;
        _lastCallStartedAt = null;
        await _clearPersistedPhoneNumber();
        await _clearPersistedCallStartedAt();

        print('   ✅ Recording found');
        print('      File: ${recording.fileName}');
        print('      Path: ${recording.filePath}');
        print('      Modified: ${recording.lastModifiedTime}');
        return;
      }

      customerCallStore.markCallCompleted(
        phoneNumber: phoneNumber,
        callEndedAt: callEndTime,
        recording: null,
      );
      _lastResolvedPhoneNumber = null;
      _lastCallStartedAt = null;
      await _clearPersistedPhoneNumber();
      await _clearPersistedCallStartedAt();
      print('   ⚠️ No recording found in the latest recorder files');
    });
  }

  Future<CallRecordingFile?> _findLatestPhoneRecording({
    required int attempt,
    required String phoneNumber,
    required DateTime? callStartedAt,
  }) async {
    print(
      '   → Recording lookup attempt $attempt/$_recordingLookupAttempts for files near ${callStartedAt ?? "unknown time"} matching $phoneNumber',
    );

    final recordings = await ServiceStarter.findRecordingsForPhone(phoneNumber);
    if (recordings.isEmpty) {
      print('   → No files matched $phoneNumber on this attempt');
      return null;
    }

    final recording = customerCallStore.selectBestRecordingForPhone(
      phoneNumber,
      recordings,
    );
    if (recording == null) {
      print('   → Files were found, but none matched the call time window');
      return null;
    }

    print('   → Time-matched file right now: ${recording.fileName}');
    return recording;
  }

  Future<void> _persistLastResolvedPhoneNumber(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber == 'Unknown') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPhoneNumberKey, phoneNumber);
  }

  Future<String?> _readPersistedPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastPhoneNumberKey);
  }

  Future<void> _clearPersistedPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastPhoneNumberKey);
  }

  Future<void> _persistLastCallStartedAt(DateTime startedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCallStartedAtKey, startedAt.millisecondsSinceEpoch);
  }

  Future<DateTime?> _readPersistedCallStartedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastCallStartedAtKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> _clearPersistedCallStartedAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCallStartedAtKey);
  }
}
