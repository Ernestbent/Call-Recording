class ErpNextSession {
  final String sessionId;
  final String userId;
  final String fullName;
  final DateTime createdAt;

  const ErpNextSession({
    required this.sessionId,
    required this.userId,
    required this.fullName,
    required this.createdAt,
  });

  factory ErpNextSession.fromJson(Map<String, dynamic> json) {
    return ErpNextSession(
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'full_name': fullName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
