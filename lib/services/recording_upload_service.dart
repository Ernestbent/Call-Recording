import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingUploadSettings {
  static const String _endpointKey = 'recording_upload_endpoint';
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

    final savedEndpoint = parseEndpoint(preferences.getString(_endpointKey));
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

class HttpRecordingUploader implements RecordingUploader {
  static const Duration _uploadTimeout = Duration(minutes: 2);

  final Uri? _endpointOverride;
  final http.Client _client;
  final RecordingUploadSettings _settings;
  final ApiCredentialProvider _credentialProvider;

  HttpRecordingUploader({
    Uri? endpoint,
    http.Client? client,
    RecordingUploadSettings? settings,
    ApiCredentialProvider? credentialProvider,
  }) : _endpointOverride = endpoint,
       _client = client ?? http.Client(),
       _settings = settings ?? RecordingUploadSettings(),
       _credentialProvider =
           credentialProvider ?? SecureAgentCredentialManager();

  @override
  bool get isConfigured => true;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
  }) async {
    final credentials = await _credentialProvider.read();
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

    try {
      final callStartedAt = DateTime.tryParse(call.createdAt);
      if (callStartedAt == null) {
        throw const RecordingUploadException(
          'This recording has an invalid call date. It remains pending.',
        );
      }
      final localCallStartedAt = callStartedAt.toLocal();

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
          'duration_seconds': '${call.duration}',
          'call_type': call.callType,
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

  static MediaType _contentTypeFor(String filePath) {
    switch (filePath.toLowerCase().split('.').last) {
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'm4a':
        return MediaType('audio', 'mp4');
      case 'wav':
        return MediaType('audio', 'wav');
      default:
        return MediaType('application', 'octet-stream');
    }
  }
}
