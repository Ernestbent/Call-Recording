class CallModel {
  final String sessionId;
  final String phoneNumber;
  final String callType;
  final int duration;
  final String audioPath;
  final String status;
  final String createdAt;

  CallModel({
    required this.sessionId,
    required this.phoneNumber,
    required this.callType,
    required this.duration,
    required this.audioPath,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'phone_number': phoneNumber,
      'call_type': callType,
      'duration': duration,
      'audio_path': audioPath,
      'status': status,
      'created_at': createdAt,
    };
  }
}