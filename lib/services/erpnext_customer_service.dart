import 'dart:async';
import 'dart:convert';

import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/utils/uganda_phone_number.dart';
import 'package:http/http.dart' as http;

abstract interface class DraftPaymentCustomerSource {
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  );
}

class ErpNextCustomerFetchException implements Exception {
  final String message;

  const ErpNextCustomerFetchException(this.message);

  @override
  String toString() => message;
}

class ErpNextCustomerService implements DraftPaymentCustomerSource {
  static const String defaultBaseUrl = 'http://127.0.0.1:8082';
  static const String _configuredBaseUrl = String.fromEnvironment(
    'ERPNEXT_BASE_URL',
    defaultValue: defaultBaseUrl,
  );
  static const int _pageLength = 100;
  static const int _customerBatchSize = 50;
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _client;
  final String baseUrl;

  ErpNextCustomerService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? _configuredBaseUrl;

  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    try {
      final draftPayments = await _fetchDraftPaymentSummaries(session);
      if (draftPayments.isEmpty) return const [];

      final customers = <DraftPaymentCustomer>[];
      final customerIds = draftPayments.keys.toList(growable: false);

      for (
        var start = 0;
        start < customerIds.length;
        start += _customerBatchSize
      ) {
        final end = (start + _customerBatchSize).clamp(0, customerIds.length);
        final batch = customerIds.sublist(start, end);
        customers.addAll(
          await _fetchCustomerBatch(
            session: session,
            customerIds: batch,
            draftPayments: draftPayments,
          ),
        );
      }

      customers.sort(
        (a, b) => a.customerName.toLowerCase().compareTo(
          b.customerName.toLowerCase(),
        ),
      );
      return customers;
    } on ErpNextCustomerFetchException {
      rethrow;
    } on TimeoutException {
      throw const ErpNextCustomerFetchException(
        'ERPNext took too long to return draft-payment customers.',
      );
    } on http.ClientException {
      throw const ErpNextCustomerFetchException(
        'Could not connect to ERPNext. Check your internet connection.',
      );
    } catch (_) {
      throw const ErpNextCustomerFetchException(
        'Could not fetch draft-payment customers from ERPNext.',
      );
    }
  }

  Future<Map<String, _DraftPaymentSummary>> _fetchDraftPaymentSummaries(
    ErpNextSession session,
  ) async {
    final summaries = <String, _DraftPaymentSummary>{};
    var start = 0;

    while (true) {
      final uri = Uri.parse('$baseUrl/api/resource/Payment%20Entry').replace(
        queryParameters: {
          'fields': jsonEncode(['name', 'party', 'creation']),
          'filters': jsonEncode([
            ['docstatus', '=', 0],
            ['party_type', '=', 'Customer'],
          ]),
          'order_by': 'modified desc',
          'limit_start': '$start',
          'limit_page_length': '$_pageLength',
        },
      );
      final rows = await _getDataRows(uri, session);

      for (final row in rows) {
        final customerId = row['party']?.toString().trim();
        if (customerId == null || customerId.isEmpty) continue;
        final createdAt = _parseErpNextDateTime(row['creation']);
        final current = summaries[customerId];
        summaries[customerId] = _DraftPaymentSummary(
          count: (current?.count ?? 0) + 1,
          latestCreatedAt: _latestDateTime(current?.latestCreatedAt, createdAt),
        );
      }

      if (rows.length < _pageLength) break;
      start += _pageLength;
    }

    return summaries;
  }

  Future<List<DraftPaymentCustomer>> _fetchCustomerBatch({
    required ErpNextSession session,
    required List<String> customerIds,
    required Map<String, _DraftPaymentSummary> draftPayments,
  }) async {
    final uri = Uri.parse('$baseUrl/api/resource/Customer').replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'customer_name', 'mobile_no', 'image']),
        'filters': jsonEncode([
          ['name', 'in', customerIds],
        ]),
        'limit_page_length': '${customerIds.length}',
      },
    );
    final rows = await _getDataRows(uri, session);

    return rows
        .map((row) {
          final customerId = row['name']?.toString().trim() ?? '';
          final rawPhoneNumber = row['mobile_no']?.toString().trim() ?? '';
          if (customerId.isEmpty || rawPhoneNumber.isEmpty) return null;
          final phoneNumber = UgandaPhoneNumber.normalize(rawPhoneNumber);

          final rawCustomerName = row['customer_name']?.toString().trim() ?? '';
          final imagePath = row['image']?.toString().trim();

          final draftPayment = draftPayments[customerId];
          return DraftPaymentCustomer(
            customerId: customerId,
            customerName: rawCustomerName.isEmpty
                ? customerId
                : rawCustomerName,
            phoneNumber: phoneNumber,
            imageUrl: _absoluteImageUrl(imagePath),
            draftPaymentCount: draftPayment?.count ?? 1,
            latestPaymentEntryCreatedAt: draftPayment?.latestCreatedAt,
          );
        })
        .whereType<DraftPaymentCustomer>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _getDataRows(
    Uri uri,
    ErpNextSession session,
  ) async {
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Cookie': 'sid=${session.sessionId}',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ErpNextCustomerFetchException(
        'Your ERPNext session cannot read Payment Entries or Customers.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ErpNextCustomerFetchException(
        'ERPNext returned ${response.statusCode} while fetching customers.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const ErpNextCustomerFetchException(
        'ERPNext returned an unexpected customer response.',
      );
    }

    return (decoded['data'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String? _absoluteImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    final uri = Uri.tryParse(imagePath);
    if (uri == null) return null;
    if (uri.hasScheme) return uri.toString();
    return Uri.parse(baseUrl).resolveUri(uri).toString();
  }

  static DateTime? _parseErpNextDateTime(Object? value) {
    final timestamp = value?.toString().trim();
    if (timestamp == null || timestamp.isEmpty) return null;
    return DateTime.tryParse(timestamp.replaceFirst(' ', 'T'));
  }

  static DateTime? _latestDateTime(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }
}

class _DraftPaymentSummary {
  final int count;
  final DateTime? latestCreatedAt;

  const _DraftPaymentSummary({
    required this.count,
    required this.latestCreatedAt,
  });
}
