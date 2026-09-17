class ApiCredentials {
  final String email;
  final String apiKey;
  final String apiSecret;

  const ApiCredentials({
    required this.email,
    required this.apiKey,
    required this.apiSecret,
  });

  factory ApiCredentials.fromJson(Map<String, dynamic> json) {
    return ApiCredentials(
      email: json['email']?.toString().trim() ?? '',
      apiKey: json['api_key']?.toString().trim() ?? '',
      apiSecret: json['api_secret']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'email': email, 'api_key': apiKey, 'api_secret': apiSecret};
  }

  bool get isComplete =>
      email.isNotEmpty && apiKey.isNotEmpty && apiSecret.isNotEmpty;

  String get authorizationHeader => 'token $apiKey:$apiSecret';

  bool belongsTo(String userEmail) =>
      email.toLowerCase() == userEmail.trim().toLowerCase();
}
