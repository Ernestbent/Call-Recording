class CallSession {
  final String phoneNumber;
  final DateTime startTime;
  final DateTime endTime;
  final String status;

  CallSession({
    required this.phoneNumber,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  String get duration {
    final diff = endTime.difference(startTime);
    return "${diff.inMinutes}m ${diff.inSeconds % 60}s";
  }

  Map<String, dynamic> toMap() {
    return {
      "phoneNumber": phoneNumber,
      "startTime": startTime.toIso8601String(),
      "endTime": endTime.toIso8601String(),
      "status": status,
    };
  }
}