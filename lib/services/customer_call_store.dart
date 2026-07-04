import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerCallStore extends ChangeNotifier {
  static const Duration _recordingWindowStartOffset = Duration(seconds: 30);
  static const Duration _recordingWindowDuration = Duration(minutes: 2);

  CustomerCallStore()
    : _customers = [
        const CustomerContact(
          name: 'Othieno Benedict Ernest',
          phoneNumber: '+256 772545948',
          subtitle: 'Renewal follow-up',
          statusLabel: 'Ready to call',
        ),
        const CustomerContact(
          name: 'Paul Kato',
          phoneNumber: '+256 725459480',
          subtitle: 'Missed callback',
          statusLabel: 'Ready to call',
        ),
        const CustomerContact(
          name: 'Sarah Namirembe',
          phoneNumber: '+256 772835195',
          subtitle: 'New lead',
          statusLabel: 'Ready to call',
        ),
      ];

  final List<CustomerContact> _customers;
  String? _queuedPhoneNumber;
  String? _activePhoneNumber;
  bool _isFetchingAllRecordings = false;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();

    for (var i = 0; i < _customers.length; i++) {
      final customer = _customers[i];
      final normalizedPhone = _normalize(customer.phoneNumber);
      if (normalizedPhone == null) {
        continue;
      }

      final startedAtMillis = prefs.getInt(_startedAtKey(normalizedPhone));
      final endedAtMillis = prefs.getInt(_endedAtKey(normalizedPhone));

      _customers[i] = customer.copyWith(
        lastCallStartedAt: startedAtMillis == null
            ? customer.lastCallStartedAt
            : DateTime.fromMillisecondsSinceEpoch(startedAtMillis),
        lastCallEndedAt: endedAtMillis == null
            ? customer.lastCallEndedAt
            : DateTime.fromMillisecondsSinceEpoch(endedAtMillis),
      );
    }

    notifyListeners();
  }

  List<CustomerContact> get customers => List.unmodifiable(_customers);
  bool get isFetchingAllRecordings => _isFetchingAllRecordings;

  int get recordingsReadyCount =>
      _customers.where((customer) => customer.latestRecording != null).length;

  Future<bool> dialCustomer(CustomerContact customer) async {
    _queuedPhoneNumber = _normalize(customer.phoneNumber);
    _updateCustomer(
      customer.phoneNumber,
      (current) => current.copyWith(
        statusLabel: 'Dialer opened',
        isCallQueued: true,
        isCallInProgress: false,
      ),
    );

    final didOpen = await ServiceStarter.openDialer(customer.phoneNumber);

    if (!didOpen) {
      _updateCustomer(
        customer.phoneNumber,
        (current) => current.copyWith(
          statusLabel: 'Could not open dialer',
          isCallQueued: false,
        ),
      );
      _queuedPhoneNumber = null;
    }

    return didOpen;
  }

  void markCallStarted(String? phoneNumber, {required DateTime startedAt}) {
    final resolvedNumber = _resolvePhoneNumber(phoneNumber);
    if (resolvedNumber == null) return;

    _activePhoneNumber = resolvedNumber;
    _updateCustomer(
      resolvedNumber,
      (current) => current.copyWith(
        statusLabel: 'Call in progress',
        lastCallStartedAt: startedAt,
        isCallQueued: false,
        isCallInProgress: true,
      ),
    );
    _persistCallTimestamps(phoneNumber: resolvedNumber, startedAt: startedAt);
  }

  void markCallCompleted({
    String? phoneNumber,
    required DateTime callEndedAt,
    CallRecordingFile? recording,
  }) {
    final resolvedNumber = _resolvePhoneNumber(phoneNumber);
    if (resolvedNumber == null) return;

    _updateCustomer(
      resolvedNumber,
      (current) => current.copyWith(
        statusLabel: recording == null
            ? 'Call ended, no recording found'
            : 'Recording ready',
        lastCallEndedAt: callEndedAt,
        latestRecording: recording,
        matchingRecordingsCount: recording == null ? 0 : 1,
        clearRecording: recording == null,
        isCallQueued: false,
        isCallInProgress: false,
      ),
    );
    _persistCallTimestamps(phoneNumber: resolvedNumber, endedAt: callEndedAt);

    _queuedPhoneNumber = null;
    _activePhoneNumber = null;
  }

  void markRecordingLookupStarted({
    String? phoneNumber,
    DateTime? callStartedAt,
    required DateTime callEndedAt,
  }) {
    final resolvedNumber = _resolvePhoneNumber(phoneNumber);
    if (resolvedNumber == null) return;

    _updateCustomer(
      resolvedNumber,
      (current) => current.copyWith(
        statusLabel: 'Scanning phone storage...',
        lastCallStartedAt: callStartedAt ?? current.lastCallStartedAt,
        lastCallEndedAt: callEndedAt,
        isCallQueued: false,
        isCallInProgress: false,
      ),
    );
  }

  Future<void> playRecording(CallRecordingFile recording) async {
    await ServiceStarter.playRecording(recording.filePath);
  }

  Future<int> fetchRecordingsForAllCustomers() async {
    if (_isFetchingAllRecordings) return recordingsReadyCount;

    _isFetchingAllRecordings = true;
    notifyListeners();

    var matchedCustomers = 0;
    final customerSnapshot = List<CustomerContact>.from(_customers);

    try {
      for (final customer in customerSnapshot) {
        _updateCustomer(
          customer.phoneNumber,
          (current) => current.copyWith(
            statusLabel: 'Checking saved recordings...',
            isCallQueued: false,
            isCallInProgress: false,
          ),
        );

        final recordings = await ServiceStarter.findRecordingsForPhone(
          customer.phoneNumber,
        );

        final currentCustomer = _customerForPhone(customer.phoneNumber) ?? customer;
        final matchingRecordings = _recordingsMatchingCallWindow(
          currentCustomer,
          recordings,
        );
        final latestRecording = matchingRecordings.isEmpty
            ? null
            : matchingRecordings.first;
        if (latestRecording != null) {
          matchedCustomers++;
        }

        _updateCustomer(
          customer.phoneNumber,
          (current) => current.copyWith(
            statusLabel: latestRecording == null
                ? 'No recordings matched the last call time'
                : 'Recording ready',
            latestRecording: latestRecording,
            matchingRecordingsCount: matchingRecordings.length,
            clearRecording: latestRecording == null,
            isCallQueued: false,
            isCallInProgress: false,
          ),
        );
      }

      return matchedCustomers;
    } finally {
      _isFetchingAllRecordings = false;
      notifyListeners();
    }
  }

  String? phoneNumberForCurrentCall(String? rawPhoneNumber) {
    return _resolvePhoneNumber(rawPhoneNumber);
  }

  CallRecordingFile? selectBestRecordingForPhone(
    String phoneNumber,
    List<CallRecordingFile> recordings,
  ) {
    final customer = _customerForPhone(phoneNumber);
    if (customer == null || recordings.isEmpty) return null;

    final matches = _recordingsMatchingCallWindow(customer, recordings);
    if (matches.isEmpty) {
      return null;
    }
    return matches.first;
  }

  void _updateCustomer(
    String phoneNumber,
    CustomerContact Function(CustomerContact current) update,
  ) {
    final normalizedTarget = _normalize(phoneNumber);
    final index = _customers.indexWhere(
      (customer) => _normalize(customer.phoneNumber) == normalizedTarget,
    );

    if (index == -1) return;

    _customers[index] = update(_customers[index]);
    notifyListeners();
  }

  CustomerContact? _customerForPhone(String phoneNumber) {
    final normalizedTarget = _normalize(phoneNumber);
    if (normalizedTarget == null) return null;

    for (final customer in _customers) {
      if (_normalize(customer.phoneNumber) == normalizedTarget) {
        return customer;
      }
    }
    return null;
  }

  List<CallRecordingFile> _recordingsMatchingCallWindow(
    CustomerContact customer,
    List<CallRecordingFile> recordings,
  ) {
    final callStartedAt = customer.lastCallStartedAt;
    if (callStartedAt == null) {
      return const <CallRecordingFile>[];
    }

    final minuteStart = DateTime(
      callStartedAt.year,
      callStartedAt.month,
      callStartedAt.day,
      callStartedAt.hour,
      callStartedAt.minute,
    ).subtract(_recordingWindowStartOffset);
    final minuteEnd = minuteStart.add(_recordingWindowDuration);

    final matches = recordings.where((recording) {
      final effectiveTimestamp = recording.effectiveTimestamp;
      final modifiedTimestamp = recording.lastModifiedTime;

      return _timestampInWindow(effectiveTimestamp, minuteStart, minuteEnd) ||
          _timestampInWindow(modifiedTimestamp, minuteStart, minuteEnd);
    }).toList()
      ..sort((a, b) {
        final aDelta =
            a.effectiveTimestamp.difference(callStartedAt).inSeconds.abs();
        final bDelta =
            b.effectiveTimestamp.difference(callStartedAt).inSeconds.abs();
        return aDelta.compareTo(bDelta);
      });

    return matches;
  }

  bool _timestampInWindow(
    DateTime timestamp,
    DateTime start,
    DateTime end,
  ) {
    return !timestamp.isBefore(start) && timestamp.isBefore(end);
  }

  String? _resolvePhoneNumber(String? rawPhoneNumber) {
    final normalized = _normalize(rawPhoneNumber);

    if (normalized != null &&
        _customers.any(
          (customer) => _normalize(customer.phoneNumber) == normalized,
        )) {
      return normalized;
    }

    return _activePhoneNumber ?? _queuedPhoneNumber;
  }

  String? _normalize(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) return null;
    return phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<void> _persistCallTimestamps({
    required String phoneNumber,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    final normalizedPhone = _normalize(phoneNumber);
    if (normalizedPhone == null) return;

    final prefs = await SharedPreferences.getInstance();

    if (startedAt != null) {
      await prefs.setInt(
        _startedAtKey(normalizedPhone),
        startedAt.millisecondsSinceEpoch,
      );
    }

    if (endedAt != null) {
      await prefs.setInt(
        _endedAtKey(normalizedPhone),
        endedAt.millisecondsSinceEpoch,
      );
    }
  }

  String _startedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_started_at';

  String _endedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_ended_at';
}
