import 'package:calls_recording/models/call_session.dart';

class SessionManager {
  CallSession? _currentSession;

  final List<CallSession> sessions = [];

  void onCallStart(String phoneNumber) {
    _currentSession = CallSession(
      phoneNumber: phoneNumber,
      startTime: DateTime.now(),
      endTime: DateTime.now(), // Placeholder, will be updated on call end
      status: "Ongoing",
    );
  }

  void onCallEnd() {
    if (_currentSession == null) return;

    final updated = CallSession(
      phoneNumber: _currentSession!.phoneNumber,
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
      status: "Pending",
    );

    sessions.add(updated);
    _currentSession = null;
  }
}