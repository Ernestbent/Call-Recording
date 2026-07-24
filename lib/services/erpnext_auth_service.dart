import 'dart:async';
import 'dart:convert';

import 'package:calls_recording/models/erpnext_session.dart';
import 'package:http/http.dart' as http;

abstract interface class ErpNextAuthenticator {
  Future<ErpNextSession> login({
    required String username,
    required String password,
  });

  Future<bool> isSessionValid(ErpNextSession session);

  Future<void> logout(ErpNextSession session);
}

class ErpNextAuthException implements Exception {
  final String message;

  const ErpNextAuthException(this.message);

  @override
  String toString() => message;
}

class ErpNextAuthService implements ErpNextAuthenticator {
  static final Uri _loginUrl = Uri.https(
    'accounting.autozonepro.org',
    '/api/method/login',
  );
  static final Uri _loggedUserUrl = Uri.https(
    'accounting.autozonepro.org',
    '/api/method/frappe.auth.get_logged_user',
  );
  static final Uri _logoutUrl = Uri.https(
    'accounting.autozonepro.org',
    '/api/method/logout',
  );
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _client;

  ErpNextAuthService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<ErpNextSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client
          .post(
            _loginUrl,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'usr': username.trim(), 'pwd': password}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ErpNextAuthException('Wrong username or password.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ErpNextAuthException(
          'Login failed. ERPNext returned ${response.statusCode}.',
        );
      }

      final sessionId = _cookieValue(response.headers['set-cookie'], 'sid');
      if (sessionId == null || sessionId.isEmpty) {
        throw const ErpNextAuthException(
          'ERPNext did not return a login session.',
        );
      }

      final responseData = _decodeObject(response.body);
      final fullName =
          responseData?['full_name']?.toString().trim() ?? username.trim();

      return ErpNextSession(
        sessionId: sessionId,
        userId: username.trim(),
        fullName: fullName.isEmpty ? username.trim() : fullName,
        createdAt: DateTime.now().toUtc(),
      );
    } on ErpNextAuthException {
      rethrow;
    } on TimeoutException {
      throw const ErpNextAuthException(
        'ERPNext took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const ErpNextAuthException(
        'Could not connect to ERPNext. Check your internet connection.',
      );
    } catch (_) {
      throw const ErpNextAuthException('Could not complete the ERPNext login.');
    }
  }

  @override
  Future<bool> isSessionValid(ErpNextSession session) async {
    try {
      final response = await _client
          .get(
            _loggedUserUrl,
            headers: {
              'Accept': 'application/json',
              'Cookie': 'sid=${session.sessionId}',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return false;

      final loggedInUser = _decodeObject(response.body)?['message']?.toString();
      return loggedInUser != null && loggedInUser != 'Guest';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> logout(ErpNextSession session) async {
    try {
      await _client
          .get(_logoutUrl, headers: {'Cookie': 'sid=${session.sessionId}'})
          .timeout(_requestTimeout);
    } catch (_) {
      // Local session removal must still succeed if ERPNext is unreachable.
    }
  }

  static String? _cookieValue(String? setCookieHeader, String name) {
    if (setCookieHeader == null) return null;
    final escapedName = RegExp.escape(name);
    return RegExp(
      '(?:^|[,;]\\s*)$escapedName=([^;,\\s]+)',
      caseSensitive: false,
    ).firstMatch(setCookieHeader)?.group(1);
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
