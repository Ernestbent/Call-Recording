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
  static const String baseUrl = 'https://accounting.autozonepro.org';
  static const int _pageLength = 100;
  static const int _customerBatchSize = 50;
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _client;

  ErpNextCustomerService({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<List<DraftPaymentCustomer>> fetchDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    try {
      final draftCounts = await _fetchDraftPaymentCustomerCounts(session);
      if (draftCounts.isEmpty) return const [];

      final customers = <DraftPaymentCustomer>[];
      final customerIds = draftCounts.keys.toList(growable: false);

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
            draftCounts: draftCounts,
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

  Future<Map<String, int>> _fetchDraftPaymentCustomerCounts(
    ErpNextSession session,
  ) async {
    final counts = <String, int>{};
    var start = 0;

    while (true) {
      final uri = Uri.parse('$baseUrl/api/resource/Payment%20Entry').replace(
        queryParameters: {
          'fields': jsonEncode(['name', 'party']),
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
        counts.update(customerId, (count) => count + 1, ifAbsent: () => 1);
      }

      if (rows.length < _pageLength) break;
      start += _pageLength;
    }

    return counts;
  }

  Future<List<DraftPaymentCustomer>> _fetchCustomerBatch({
    required ErpNextSession session,
    required List<String> customerIds,
    required Map<String, int> draftCounts,
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

          return DraftPaymentCustomer(
            customerId: customerId,
            customerName: rawCustomerName.isEmpty
                ? customerId
                : rawCustomerName,
            phoneNumber: phoneNumber,
            imageUrl: _absoluteImageUrl(imagePath),
            draftPaymentCount: draftCounts[customerId] ?? 1,
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
}
