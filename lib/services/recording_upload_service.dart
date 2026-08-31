import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/api_credentials.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingUploadSettings {
  static const String _endpointKey = 'recording_upload_endpoint';
  static const Set<String> _legacyLocalEndpoints = {
    'http://127.0.0.1:8002/api/mobile/cal-logs/',
    'http://127.0.0.1:8002/api/mobile/call-logs/',
  };
  static final Uri defaultEndpoint = Uri.parse(
    'https://erp.autozonepro.org/api/mobile/call-logs/',
  );
  static const String _initialEndpoint = String.fromEnvironment(
    'RECORDING_UPLOAD_INITIAL_URL',
  );

  Future<Uri?> readEndpoint() async {
    final preferences = await SharedPreferences.getInstance();
    final initialEndpoint = parseEndpoint(_initialEndpoint);
    if (initialEndpoint != null) {
      await preferences.setString(_endpointKey, initialEndpoint.toString());
      return initialEndpoint;
    }

    final savedEndpointValue = preferences.getString(_endpointKey);
    if (_legacyLocalEndpoints.contains(savedEndpointValue)) {
      await preferences.setString(_endpointKey, defaultEndpoint.toString());
      return defaultEndpoint;
    }

    final savedEndpoint = parseEndpoint(savedEndpointValue);
    if (savedEndpoint != null) return savedEndpoint;
    return defaultEndpoint;
  }

  Future<void> saveEndpoint(String value) async {
    final endpoint = parseEndpoint(value);
    if (endpoint == null) {
      throw const FormatException(
        'Enter a valid HTTP or HTTPS recording API URL.',
      );
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_endpointKey, endpoint.toString());
  }

  static Uri? parseEndpoint(String? value) {
    final endpoint = value == null ? null : Uri.tryParse(value.trim());
    if (endpoint == null ||
        !endpoint.hasScheme ||
        (endpoint.scheme != 'https' && endpoint.scheme != 'http') ||
        endpoint.host.isEmpty) {
      return null;
    }
    return endpoint;
  }
}

abstract interface class RecordingUploader {
  bool get isConfigured;

  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
    String? agentEmail,
  });
}

class RecordingUploadResult {
  final String uploadId;
  final String message;

  const RecordingUploadResult({required this.uploadId, required this.message});
}

class RecordingUploadException implements Exception {
  final String message;

  const RecordingUploadException(this.message);

  @override
  String toString() => message;
}

class RecordingFileReadiness {
  final int sizeBytes;
  final int durationSeconds;

  const RecordingFileReadiness({
    required this.sizeBytes,
    required this.durationSeconds,
  });
}

abstract interface class RecordingFileInspector {
  Future<RecordingFileReadiness?> waitUntilReady(String filePath);
}

typedef RecordingDurationReader = Future<int?> Function(String filePath);

class DeviceRecordingFileInspector implements RecordingFileInspector {
  final int maxAttempts;
  final Duration retryDelay;
  final RecordingDurationReader durationReader;

  DeviceRecordingFileInspector({
    this.maxAttempts = 6,
    this.retryDelay = const Duration(seconds: 2),
    RecordingDurationReader? durationReader,
  }) : durationReader =
           durationReader ?? ServiceStarter.getRecordingDurationMillis;

  @override
  Future<RecordingFileReadiness?> waitUntilReady(String filePath) async {
    final recording = File(filePath);
    int? previousSize;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!await recording.exists()) return null;

      final sizeBytes = await recording.length();
      final durationMillis = sizeBytes > 0
          ? await durationReader(filePath)
          : null;
      final isStable = sizeBytes > 0 && sizeBytes == previousSize;

      debugPrint(
        'RECORDING_UPLOAD: readiness attempt=$attempt/$maxAttempts '
        'size=$sizeBytes stable=$isStable durationMs=${durationMillis ?? 0}',
      );

      if (isStable && durationMillis != null && durationMillis > 0) {
        return RecordingFileReadiness(
          sizeBytes: sizeBytes,
          durationSeconds: (durationMillis / 1000).ceil(),
        );
      }

      previousSize = sizeBytes;
      if (attempt < maxAttempts) {
        await Future<void>.delayed(retryDelay);
      }
    }

    return null;
  }
}

class HttpRecordingUploader implements RecordingUploader {
  static const Duration _uploadTimeout = Duration(minutes: 2);

  final Uri? _endpointOverride;
  final http.Client _client;
  final RecordingUploadSettings _settings;
  final ApiCredentialProvider _credentialProvider;
  final RecordingFileInspector _fileInspector;

  HttpRecordingUploader({
    Uri? endpoint,
    http.Client? client,
    RecordingUploadSettings? settings,
    ApiCredentialProvider? credentialProvider,
    RecordingFileInspector? fileInspector,
  }) : _endpointOverride = endpoint,
       _client = client ?? http.Client(),
       _settings = settings ?? RecordingUploadSettings(),
       _credentialProvider =
           credentialProvider ?? SecureAgentCredentialManager(),
       _fileInspector = fileInspector ?? DeviceRecordingFileInspector();

  @override
  bool get isConfigured => true;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
    String? agentEmail,
  }) async {
    final credentials = await _credentialsForAgent(agentEmail);
    if (credentials == null) {
      throw const RecordingUploadException(
        'Sign in again before uploading recordings.',
      );
    }

    final endpoint = _endpointOverride ?? await _settings.readEndpoint();
    if (endpoint == null) {
      throw const RecordingUploadException(
        'Set the recording API URL in Settings before uploading.',
      );
    }

    final normalizedCustomerId = customerId?.trim() ?? '';
    if (normalizedCustomerId.isEmpty) {
      throw const RecordingUploadException(
        'This recording has no ERPNext customer ID. It remains pending.',
      );
    }

    final recording = File(call.audioPath);
    if (!await recording.exists()) {
      throw const RecordingUploadException(
        'The recording file no longer exists on this phone.',
      );
    }
    if (_isAppMicrophoneRecording(recording.path)) {
      throw const RecordingUploadException(
        'This is an app microphone recording, not the phone dialer recording. '
        'It remains pending.',
      );
    }

    final readiness = await _fileInspector.waitUntilReady(call.audioPath);
    if (readiness == null) {
      throw const RecordingUploadException(
        'The recording is empty or still being finalized. It remains pending.',
      );
    }

    final durationSeconds = readiness.durationSeconds;
    if (durationSeconds <= 0) {
      throw const RecordingUploadException(
        'The recording duration is not ready. It remains pending.',
      );
    }

    try {
      final callStartedAt = DateTime.tryParse(call.createdAt);
      if (callStartedAt == null) {
        throw const RecordingUploadException(
          'This recording has an invalid call date. It remains pending.',
        );
      }
      final localCallStartedAt = callStartedAt.toLocal();

      debugPrint(
        'RECORDING_UPLOAD: POST $endpoint '
        'session=${call.sessionId} customer=$normalizedCustomerId '
        'agent=${agentEmail?.trim().isNotEmpty == true ? agentEmail!.trim() : "(none)"} '
        'file=${recording.path.split(Platform.pathSeparator).last} '
        'bytes=${readiness.sizeBytes} duration=$durationSeconds',
      );

      final request = http.MultipartRequest('POST', endpoint)
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization':
              'token ${credentials.apiKey}:${credentials.apiSecret}',
        })
        ..fields.addAll({
          'device_local_id': call.sessionId,
          'customer_id': normalizedCustomerId,
          'mobile_no': call.phoneNumber,
          'call_date': _formatDate(localCallStartedAt),
          'call_time': _formatTime(localCallStartedAt),
          'duration_seconds': '$durationSeconds',
          'call_type': call.callType,
          if (agentEmail != null && agentEmail.trim().isNotEmpty)
            'agent_username': agentEmail.trim(),
        })
        ..files.add(
          await http.MultipartFile.fromPath(
            'audio_file',
            call.audioPath,
            contentType: _contentTypeFor(call.audioPath),
          ),
        );

      final streamedResponse = await _client
          .send(request)
          .timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
        'RECORDING_UPLOAD: response ${response.statusCode} '
        'session=${call.sessionId} body=${_debugBody(response.body)}',
      );

      if (response.statusCode == 401) {
        throw const RecordingUploadException(
          'Upload credentials were rejected. Sign in again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final serverError = _serverError(response.body);
        throw RecordingUploadException(
          serverError ??
              'Upload server returned ${response.statusCode}. It remains pending.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw const RecordingUploadException(
          'Upload server did not confirm the recording.',
        );
      }

      final callLog = decoded['call_log'];
      final uploadId = callLog is Map
          ? callLog['id']?.toString().trim() ?? ''
          : '';
      if (uploadId.isEmpty) {
        throw const RecordingUploadException(
          'Upload server did not return a call-log ID.',
        );
      }

      return RecordingUploadResult(
        uploadId: uploadId,
        message:
            decoded['message']?.toString() ??
            'Recording uploaded successfully.',
      );
    } on RecordingUploadException {
      rethrow;
    } on TimeoutException {
      throw const RecordingUploadException(
        'Recording upload took too long. It remains pending.',
      );
    } on SocketException {
      throw const RecordingUploadException(
        'Could not reach the recording server. It remains pending.',
      );
    } on http.ClientException {
      throw const RecordingUploadException(
        'Could not send the recording. It remains pending.',
      );
    } catch (_) {
      throw const RecordingUploadException(
        'Could not upload the recording. It remains pending.',
      );
    }
  }

  bool _isAppMicrophoneRecording(String filePath) {
    final normalizedPath = filePath.replaceAll('\\', '/').toLowerCase();
    return normalizedPath.contains('/app_flutter/recordings/');
  }

  Future<ApiCredentials?> _credentialsForAgent(String? agentEmail) async {
    final normalizedEmail = agentEmail?.trim().toLowerCase() ?? '';
    final savedCredentials = await _credentialProvider.read();

    if (normalizedEmail.isNotEmpty &&
        _credentialProvider is AgentCredentialManager) {
      try {
        debugPrint(
          'RECORDING_UPLOAD: activating credentials for $normalizedEmail',
        );
        return await _credentialProvider.activateForEmail(normalizedEmail);
      } on AgentCredentialException catch (error) {
        throw RecordingUploadException(error.message);
      }
    }

    if (savedCredentials != null &&
        (normalizedEmail.isEmpty ||
            savedCredentials.belongsTo(normalizedEmail))) {
      debugPrint(
        'RECORDING_UPLOAD: using saved credentials '
        'agent=${savedCredentials.email}',
      );
      return savedCredentials;
    }

    if (normalizedEmail.isEmpty ||
        _credentialProvider is! AgentCredentialManager) {
      debugPrint(
        'RECORDING_UPLOAD: using saved credentials without agent match '
        'agent=${savedCredentials?.email ?? "(none)"}',
      );
      return savedCredentials;
    }

    return savedCredentials;
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String? _serverError(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return null;
      final error = decoded['error']?.toString().trim();
      return error == null || error.isEmpty ? null : error;
    } catch (_) {
      return null;
    }
  }

  static String _debugBody(String responseBody) {
    final compact = responseBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '(empty)';
    return compact.length <= 180 ? compact : '${compact.substring(0, 180)}...';
  }

  static MediaType _contentTypeFor(String filePath) {
    switch (filePath.toLowerCase().split('.').last) {
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'm4a':
        return MediaType('audio', 'mp4');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'aac':
        return MediaType('audio', 'aac');
      case 'amr':
        return MediaType('audio', 'amr');
      case '3gp':
        return MediaType('audio', '3gpp');
      case 'ogg':
      case 'opus':
        return MediaType('audio', 'ogg');
      default:
        return MediaType('application', 'octet-stream');
    }
  }
}
