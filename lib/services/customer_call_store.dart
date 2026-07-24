import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerCallStore extends ChangeNotifier {
  static const Duration _recordingWindowStartOffset = Duration(seconds: 30);
  static const Duration _recordingWindowDuration = Duration(minutes: 2);

  CustomerCallStore({
    CallPersistence? callPersistence,
    DraftPaymentCustomerSource? customerSource,
    List<CustomerContact> initialCustomers = const [],
  }) : _callPersistence = callPersistence ?? CallRepository(),
       _customerSource = customerSource ?? ErpNextCustomerService(),
       _customers = List<CustomerContact>.from(initialCustomers) {
    initializePlaybackEvents();
  }

  final List<CustomerContact> _customers;
  final CallPersistence _callPersistence;
  final DraftPaymentCustomerSource _customerSource;
  ErpNextSession? _activeErpNextSession;
  String? _queuedPhoneNumber;
  String? _activePhoneNumber;
  String? _activeRecordingPath;
  bool _isFetchingAllRecordings = false;
  bool _isLoadingCustomers = false;
  bool _isRecordingPlaying = false;
  String? _customerLoadError;

  void initializePlaybackEvents() {
    ServiceStarter.configurePlaybackEvents(
      onCompleted: _handlePlaybackEnded,
      onFailed: _handlePlaybackEnded,
    );
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();

    for (var i = 0; i < _customers.length; i++) {
      _customers[i] = _withPersistedCallTimestamps(_customers[i], prefs);
    }

    notifyListeners();
  }

  List<CustomerContact> get customers => List.unmodifiable(_customers);
  bool get isFetchingAllRecordings => _isFetchingAllRecordings;
  bool get isLoadingCustomers => _isLoadingCustomers;
  String? get customerLoadError => _customerLoadError;

  int get recordingsReadyCount =>
      _customers.where((customer) => customer.latestRecording != null).length;

  bool isActiveRecording(CallRecordingFile recording) =>
      _activeRecordingPath == recording.filePath;

  bool isPlayingRecording(CallRecordingFile recording) =>
      isActiveRecording(recording) && _isRecordingPlaying;

  Future<int> loadDraftPaymentCustomers(ErpNextSession session) async {
    if (_isLoadingCustomers) return _customers.length;

    _activeErpNextSession = session;
    _isLoadingCustomers = true;
    _customerLoadError = null;
    notifyListeners();

    try {
      final remoteCustomers = await _customerSource.fetchDraftPaymentCustomers(
        session,
      );
      final prefs = await SharedPreferences.getInstance();
      final refreshedCustomers = <CustomerContact>[];

      for (final remoteCustomer in remoteCustomers) {
        final previous =
            _customerForErpNextId(remoteCustomer.customerId) ??
            _customerForPhone(remoteCustomer.phoneNumber);
        final draftLabel = remoteCustomer.draftPaymentCount == 1
            ? '1 draft payment entry'
            : '${remoteCustomer.draftPaymentCount} draft payment entries';
        final imageHeaders = _authenticatedImageHeaders(
          imageUrl: remoteCustomer.imageUrl,
          session: session,
        );

        final refreshed = CustomerContact(
          erpNextCustomerId: remoteCustomer.customerId,
          name: remoteCustomer.customerName,
          phoneNumber: remoteCustomer.phoneNumber,
          profileImageUrl: remoteCustomer.imageUrl,
          profileImageHeaders: imageHeaders,
          draftPaymentCount: remoteCustomer.draftPaymentCount,
          subtitle: draftLabel,
          statusLabel: previous?.statusLabel ?? 'Ready to call',
          lastCallStartedAt: previous?.lastCallStartedAt,
          lastCallEndedAt: previous?.lastCallEndedAt,
          latestRecording: previous?.latestRecording,
          availableRecordings: previous?.availableRecordings ?? const [],
          matchingRecordingsCount: previous?.matchingRecordingsCount ?? 0,
          isCallQueued: previous?.isCallQueued ?? false,
          isCallInProgress: previous?.isCallInProgress ?? false,
        );
        refreshedCustomers.add(_withPersistedCallTimestamps(refreshed, prefs));
      }

      _customers
        ..clear()
        ..addAll(refreshedCustomers);
      return _customers.length;
    } on ErpNextCustomerFetchException catch (error) {
      _customerLoadError = error.message;
      return _customers.length;
    } catch (_) {
      _customerLoadError =
          'Could not refresh draft-payment customers from ERPNext.';
      return _customers.length;
    } finally {
      _isLoadingCustomers = false;
      notifyListeners();
    }
  }

  Future<int> refreshDraftPaymentCustomers() async {
    final session = _activeErpNextSession;
    if (session == null) {
      _customerLoadError = 'Log in to ERPNext before refreshing customers.';
      notifyListeners();
      return _customers.length;
    }
    return loadDraftPaymentCustomers(session);
  }

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

  Future<void> markCallCompleted({
    String? phoneNumber,
    required DateTime callEndedAt,
    CallRecordingFile? recording,
  }) async {
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
        availableRecordings: recording == null ? const [] : [recording],
        matchingRecordingsCount: recording == null ? 0 : 1,
        clearRecording: recording == null,
        isCallQueued: false,
        isCallInProgress: false,
      ),
    );
    await _persistCallTimestamps(
      phoneNumber: resolvedNumber,
      endedAt: callEndedAt,
    );

    if (recording != null) {
      final customer = _customerForPhone(resolvedNumber);
      if (customer != null) {
        await _saveMatchedRecording(customer: customer, recording: recording);
      }
    }

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

  Future<bool> playRecording(CallRecordingFile recording) {
    return toggleRecordingPlayback(recording);
  }

  Future<bool> toggleRecordingPlayback(CallRecordingFile recording) async {
    final isCurrentRecording = isActiveRecording(recording);
    if (isCurrentRecording && _isRecordingPlaying) {
      final didPause = await ServiceStarter.pauseRecording();
      if (didPause) {
        _isRecordingPlaying = false;
        notifyListeners();
      }
      return didPause;
    }

    if (isCurrentRecording) {
      final didResume = await ServiceStarter.resumeRecording();
      if (didResume) {
        _isRecordingPlaying = true;
        notifyListeners();
      }
      return didResume;
    }

    final didStart = await ServiceStarter.playRecording(recording.filePath);
    if (didStart) {
      _activeRecordingPath = recording.filePath;
      _isRecordingPlaying = true;
      notifyListeners();
    }
    return didStart;
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

        final currentCustomer =
            _customerForPhone(customer.phoneNumber) ?? customer;
        final matchingRecordings = _recordingsMatchingCallWindow(
          currentCustomer,
          recordings,
        );
        final latestRecording = matchingRecordings.isEmpty
            ? null
            : matchingRecordings.first;
        if (latestRecording != null) {
          matchedCustomers++;
          await _saveMatchedRecording(
            customer: currentCustomer,
            recording: latestRecording,
          );
        }

        _updateCustomer(
          customer.phoneNumber,
          (current) => current.copyWith(
            statusLabel: latestRecording == null
                ? current.lastCallStartedAt == null
                      ? 'No call has been started from this app'
                      : 'No recordings matched the last app call'
                : '${matchingRecordings.length} recording${matchingRecordings.length == 1 ? '' : 's'} matched the last app call',
            latestRecording: latestRecording,
            availableRecordings: matchingRecordings,
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

  CustomerContact? _customerForErpNextId(String customerId) {
    for (final customer in _customers) {
      if (customer.erpNextCustomerId == customerId) {
        return customer;
      }
    }
    return null;
  }

  Map<String, String> _authenticatedImageHeaders({
    required String? imageUrl,
    required ErpNextSession session,
  }) {
    final uri = imageUrl == null ? null : Uri.tryParse(imageUrl);
    if (uri == null || uri.host != 'accounting.autozonepro.org') {
      return const {};
    }
    return {'Cookie': 'sid=${session.sessionId}'};
  }

  CustomerContact _withPersistedCallTimestamps(
    CustomerContact customer,
    SharedPreferences prefs,
  ) {
    final normalizedPhone = _normalize(customer.phoneNumber);
    if (normalizedPhone == null) return customer;

    final startedAtMillis = prefs.getInt(_startedAtKey(normalizedPhone));
    final endedAtMillis = prefs.getInt(_endedAtKey(normalizedPhone));

    return customer.copyWith(
      lastCallStartedAt: startedAtMillis == null
          ? customer.lastCallStartedAt
          : DateTime.fromMillisecondsSinceEpoch(startedAtMillis),
      lastCallEndedAt: endedAtMillis == null
          ? customer.lastCallEndedAt
          : DateTime.fromMillisecondsSinceEpoch(endedAtMillis),
    );
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

    final matches =
        recordings.where((recording) {
          final effectiveTimestamp = recording.effectiveTimestamp;
          final modifiedTimestamp = recording.lastModifiedTime;

          return _timestampInWindow(
                effectiveTimestamp,
                minuteStart,
                minuteEnd,
              ) ||
              _timestampInWindow(modifiedTimestamp, minuteStart, minuteEnd);
        }).toList()..sort((a, b) {
          final aDelta = a.effectiveTimestamp
              .difference(callStartedAt)
              .inSeconds
              .abs();
          final bDelta = b.effectiveTimestamp
              .difference(callStartedAt)
              .inSeconds
              .abs();
          return aDelta.compareTo(bDelta);
        });

    return matches;
  }

  bool _timestampInWindow(DateTime timestamp, DateTime start, DateTime end) {
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

  Future<void> _saveMatchedRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
  }) async {
    final startedAt = customer.lastCallStartedAt;
    if (startedAt == null) return;

    final endedAt = customer.lastCallEndedAt ?? recording.lastModifiedTime;
    final durationSeconds = endedAt.isAfter(startedAt)
        ? endedAt.difference(startedAt).inSeconds
        : 0;
    final normalizedPhone =
        _normalize(customer.phoneNumber) ?? customer.phoneNumber;
    final sessionId =
        'call_${normalizedPhone.replaceAll(RegExp(r"[^0-9]"), "")}_${startedAt.millisecondsSinceEpoch}';

    final call = CallModel(
      sessionId: sessionId,
      phoneNumber: customer.phoneNumber,
      callType: 'outgoing',
      duration: durationSeconds,
      audioPath: recording.filePath,
      status: 'pending',
      createdAt: startedAt.toIso8601String(),
    );

    await _callPersistence.saveCall(call.toMap());
  }

  String _startedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_started_at';

  String _endedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_ended_at';

  void _handlePlaybackEnded(String filePath) {
    if (_activeRecordingPath != filePath) return;
    _activeRecordingPath = null;
    _isRecordingPlaying = false;
    notifyListeners();
  }
}
