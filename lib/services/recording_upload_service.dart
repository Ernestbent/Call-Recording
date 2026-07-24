import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calls_recording/db/call_model.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingUploadSettings {
  static const String _endpointKey = 'recording_upload_endpoint';
  static const String _initialEndpoint = String.fromEnvironment(
    'RECORDING_UPLOAD_INITIAL_URL',
  );

  Future<Uri?> readEndpoint() async {
    final preferences = await SharedPreferences.getInstance();
    final savedEndpoint = parseEndpoint(preferences.getString(_endpointKey));
    if (savedEndpoint != null) return savedEndpoint;

    final initialEndpoint = parseEndpoint(_initialEndpoint);
    if (initialEndpoint != null) {
      await preferences.setString(_endpointKey, initialEndpoint.toString());
    }
    return initialEndpoint;
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
  static const String _configuredToken = String.fromEnvironment(
    'RECORDING_UPLOAD_TOKEN',
  );
  static const Duration _uploadTimeout = Duration(minutes: 2);

  final Uri? _endpointOverride;
  final String bearerToken;
  final http.Client _client;
  final RecordingUploadSettings _settings;

  HttpRecordingUploader({
    Uri? endpoint,
    String? bearerToken,
    http.Client? client,
    RecordingUploadSettings? settings,
  }) : _endpointOverride = endpoint,
       bearerToken = bearerToken ?? _configuredToken,
       _client = client ?? http.Client(),
       _settings = settings ?? RecordingUploadSettings();

  @override
  bool get isConfigured => bearerToken.trim().isNotEmpty;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
  }) async {
    if (!isConfigured) {
      throw const RecordingUploadException(
        'The recording upload token is not configured.',
      );
    }

    final endpoint = _endpointOverride ?? await _settings.readEndpoint();
    if (endpoint == null) {
      throw const RecordingUploadException(
        'Set the recording API URL in Settings before uploading.',
      );
    }

    final recording = File(call.audioPath);
    if (!await recording.exists()) {
      throw const RecordingUploadException(
        'The recording file no longer exists on this phone.',
      );
    }

    try {
      final request = http.MultipartRequest('POST', endpoint)
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer ${bearerToken.trim()}',
          'ngrok-skip-browser-warning': 'true',
        })
        ..fields.addAll({
          'session_id': call.sessionId,
          'phone_number': call.phoneNumber,
          'call_type': call.callType,
          'duration': '${call.duration}',
          'created_at': call.createdAt,
          if (customerId != null && customerId.trim().isNotEmpty)
            'customer_id': customerId.trim(),
        })
        ..files.add(
          await http.MultipartFile.fromPath(
            'recording',
            call.audioPath,
            contentType: _contentTypeFor(call.audioPath),
          ),
        );

      final streamedResponse = await _client
          .send(request)
          .timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RecordingUploadException(
          'Upload server returned ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw const RecordingUploadException(
          'Upload server did not confirm the recording.',
        );
      }

      final uploadId = decoded['upload_id']?.toString().trim() ?? '';
      if (uploadId.isEmpty) {
        throw const RecordingUploadException(
          'Upload server did not return an upload ID.',
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
