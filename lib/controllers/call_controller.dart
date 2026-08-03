import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/services/call_manager.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/session_manager.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter/foundation.dart';
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
    debugPrint('\n════════════════════════════════════════════════════');
    debugPrint('🚀 INITIALIZING CALL CONTROLLER');
    debugPrint('════════════════════════════════════════════════════\n');

    // Request permissions
    debugPrint('Step 1: Requesting permissions...');
    final granted = await callManager.requestPermissions();

    if (!granted) {
      debugPrint('\n❌ PERMISSIONS DENIED - Cannot continue!');
      debugPrint('════════════════════════════════════════════════════\n');
      return;
    }

    // Start listening
    debugPrint('\nStep 2: Starting phone state listener...');
    callManager.startListening((PhoneState event) {
      _handleCallEvent(event);
    });

    debugPrint('\n✅ CALL CONTROLLER INITIALIZED SUCCESSFULLY');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('⏳ Waiting for phone calls...\n');
  }

  // Handle call events
  Future<void> _handleCallEvent(PhoneState event) async {
    final status = event.status;
    final number = event.number ?? 'Unknown';

    debugPrint('\n⚡ HANDLING CALL EVENT');
    debugPrint('   Status Type: $status');
    debugPrint('   Phone Number: $number');

    // Call started (incoming or outgoing)
    if (status == PhoneStateStatus.CALL_STARTED) {
      debugPrint('\n🔴 ▶️ CALL STARTED!');
      debugPrint('   → Phone number: $number');

      try {
        final callStartedAt = DateTime.now();
        final resolvedPhoneNumber =
            customerCallStore.phoneNumberForCurrentCall(event.number) ??
            event.number;

        _lastResolvedPhoneNumber = resolvedPhoneNumber;
        _lastCallStartedAt = callStartedAt;
        await _persistLastResolvedPhoneNumber(resolvedPhoneNumber);
        await _persistLastCallStartedAt(callStartedAt);

        debugPrint('   → Notifying SessionManager...');
        sessionManager.onCallStart(number);
        debugPrint('   ✅ SessionManager notified');

        customerCallStore.markCallStarted(
          resolvedPhoneNumber,
          startedAt: callStartedAt,
        );

        debugPrint('   → Starting Android recording service...');
        await ServiceStarter.startService();
        debugPrint('   ✅ Recording service started');
      } catch (e) {
        debugPrint('   ❌ Error: $e');
      }
    }
    // Call ended
    else if (status == PhoneStateStatus.CALL_ENDED) {
      debugPrint('\n🟢 ⏹️ CALL ENDED!');
      debugPrint('   → Phone number: $number');

      try {
        final callEndTime = DateTime.now();

        debugPrint('   → Notifying SessionManager...');
        sessionManager.onCallEnd();
        debugPrint('   ✅ SessionManager notified');

        final lookupPhoneNumber =
            customerCallStore.phoneNumberForCurrentCall(event.number) ??
            _lastResolvedPhoneNumber ??
            await _readPersistedPhoneNumber();
        final callStartedAt =
            _lastCallStartedAt ?? await _readPersistedCallStartedAt();

        if (lookupPhoneNumber == null || lookupPhoneNumber == 'Unknown') {
          debugPrint(
            '   ⚠️ No resolved phone number available for recording lookup',
          );
          return;
        }

        customerCallStore.markRecordingLookupStarted(
          phoneNumber: lookupPhoneNumber,
          callStartedAt: callStartedAt,
          callEndedAt: callEndTime,
        );

        debugPrint('   → Scheduling recording lookup...');
        _scheduleRecordingLookup(
          phoneNumber: lookupPhoneNumber,
          callStartedAt: callStartedAt,
          callEndTime: callEndTime,
        );
      } catch (e) {
        debugPrint('   ❌ Error: $e');
      }
    } else {
      debugPrint('\n❓ OTHER STATE: $status');
    }

    debugPrint('');
  }

  // Stop listening
  void dispose() {
    debugPrint('\n🛑 Disposing CallController...');
    callManager.stopListening();
    debugPrint('✅ CallController disposed\n');
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

        await customerCallStore.markCallCompleted(
          phoneNumber: phoneNumber,
          callEndedAt: callEndTime,
          recording: recording,
        );

        _lastResolvedPhoneNumber = null;
        _lastCallStartedAt = null;
        await _clearPersistedPhoneNumber();
        await _clearPersistedCallStartedAt();

        debugPrint('   ✅ Recording found');
        debugPrint('      File: ${recording.fileName}');
        debugPrint('      Path: ${recording.filePath}');
        debugPrint('      Modified: ${recording.lastModifiedTime}');
        return;
      }

      await customerCallStore.markCallCompleted(
        phoneNumber: phoneNumber,
        callEndedAt: callEndTime,
        recording: null,
      );
      _lastResolvedPhoneNumber = null;
      _lastCallStartedAt = null;
      await _clearPersistedPhoneNumber();
      await _clearPersistedCallStartedAt();
      debugPrint('   ⚠️ No recording found in the latest recorder files');
    });
  }

  Future<CallRecordingFile?> _findLatestPhoneRecording({
    required int attempt,
    required String phoneNumber,
    required DateTime? callStartedAt,
  }) async {
    debugPrint(
      '   → Recording lookup attempt $attempt/$_recordingLookupAttempts for files near ${callStartedAt ?? "unknown time"} matching $phoneNumber',
    );

    final recordings = await ServiceStarter.findRecordingsForPhone(phoneNumber);
    if (recordings.isEmpty) {
      debugPrint('   → No files matched $phoneNumber on this attempt');
      return null;
    }

    final recording = customerCallStore.selectBestRecordingForPhone(
      phoneNumber,
      recordings,
    );
    if (recording == null) {
      debugPrint(
        '   → Files were found, but none matched the call time window',
      );
      return null;
    }

    debugPrint('   → Time-matched file right now: ${recording.fileName}');
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
