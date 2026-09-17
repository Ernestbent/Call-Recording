import 'dart:async';
import 'dart:convert';

import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/draft_payment_customer.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/models/persisted_call_session.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/erpnext_customer_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/services/service_starter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RecordingUploadState { pending, uploading, uploaded, failed }

class RecordingBatchUploadResult {
  final int total;
  final int attempted;
  final int uploaded;
  final int failed;
  final int alreadyUploaded;

  const RecordingBatchUploadResult({
    required this.total,
    required this.attempted,
    required this.uploaded,
    required this.failed,
    required this.alreadyUploaded,
  });
}

class _PendingRecordingUpload {
  final CustomerContact customer;
  final CallRecordingFile recording;
  final CallModel call;

  const _PendingRecordingUpload({
    required this.customer,
    required this.recording,
    required this.call,
  });
}

class CustomerCallStore extends ChangeNotifier {
  static const List<Duration> _defaultAutomaticUploadRetryDelays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  static const Duration _defaultDraftCustomerRefreshInterval = Duration(
    minutes: 15,
  );
  static const Duration _defaultRecordingDiscoveryTimeout = Duration(
    minutes: 15,
  );
  static const Duration _defaultSessionHistoryRetention = Duration(days: 30);
  static const Duration _recordingWindowStartOffset = Duration(seconds: 30);
  static const Duration _recordingWindowDuration = Duration(minutes: 2);
  static const Duration _duplicateCallTolerance = Duration(seconds: 15);
  static const String _erpNextBaseUrl = String.fromEnvironment(
    'ERPNEXT_BASE_URL',
    defaultValue: 'https://accounting.autozonepro.org',
  );
  static const String _testRecordingPhoneNumber = String.fromEnvironment(
    'TEST_RECORDING_PHONE_NUMBER',
  );
  static const String _darkModeKey = 'app_dark_mode_enabled';
  static const String _completedPaymentEntriesKey =
      'completed_draft_payment_entry_ids';
  static const String _draftCustomerCachePrefix =
      'draft_payment_customer_cache_';
  static const String _callSessionLedgerKey = 'persistent_call_session_ledger';
  static const Duration _persistedWorkInterval = Duration(minutes: 1);

  CustomerCallStore({
    CallPersistence? callPersistence,
    DraftPaymentCustomerSource? customerSource,
    RecordingUploader? recordingUploader,
    List<Duration> automaticUploadRetryDelays =
        _defaultAutomaticUploadRetryDelays,
    Duration draftCustomerRefreshInterval =
        _defaultDraftCustomerRefreshInterval,
    bool automaticDraftCustomerRefreshEnabled = true,
    bool? automaticPersistedWorkEnabled,
    Duration recordingDiscoveryTimeout = _defaultRecordingDiscoveryTimeout,
    Duration sessionHistoryRetention = _defaultSessionHistoryRetention,
    DateTime Function()? now,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    List<CustomerContact> initialCustomers = const [],
  }) : _callPersistence = callPersistence ?? CallRepository(),
       _customerSource = customerSource ?? ErpNextCustomerService(),
       _recordingUploader = recordingUploader ?? HttpRecordingUploader(),
       _automaticUploadRetryDelays = List.unmodifiable(
         automaticUploadRetryDelays,
       ),
       _draftCustomerRefreshInterval = draftCustomerRefreshInterval,
       _automaticDraftCustomerRefreshEnabled =
           automaticDraftCustomerRefreshEnabled,
       _automaticPersistedWorkEnabled =
           automaticPersistedWorkEnabled ??
           automaticDraftCustomerRefreshEnabled,
       _recordingDiscoveryTimeout = recordingDiscoveryTimeout,
       _sessionHistoryRetention = sessionHistoryRetention,
       _now = now ?? DateTime.now,
       _customers = List<CustomerContact>.from(initialCustomers) {
    if (_automaticUploadRetryDelays.isEmpty) {
      throw ArgumentError.value(
        automaticUploadRetryDelays,
        'automaticUploadRetryDelays',
        'At least one retry delay is required.',
      );
    }
    initializePlaybackEvents();
    _connectivitySubscription =
        (connectivityChanges ?? Connectivity().onConnectivityChanged).listen(
          _handleConnectivityChanged,
        );
  }

  final List<CustomerContact> _customers;
  final List<PersistedCallSession> _callSessions = [];
  final CallPersistence _callPersistence;
  final DraftPaymentCustomerSource _customerSource;
  final RecordingUploader _recordingUploader;
  final List<Duration> _automaticUploadRetryDelays;
  final Duration _draftCustomerRefreshInterval;
  final bool _automaticDraftCustomerRefreshEnabled;
  final bool _automaticPersistedWorkEnabled;
  final Duration _recordingDiscoveryTimeout;
  final Duration _sessionHistoryRetention;
  final DateTime Function() _now;
  final Map<String, RecordingUploadState> _recordingUploadStates = {};
  final Map<String, Timer> _automaticUploadRetryTimers = {};
  final Map<String, int> _automaticUploadRetryAttempts = {};
  final Map<String, _PendingRecordingUpload> _pendingRecordingUploads = {};
  final Set<String> _completedPaymentEntryIds = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _draftCustomerRefreshTimer;
  Timer? _persistedWorkTimer;
  bool? _wasDisconnected;
  DateTime? _lastDraftCustomerRefreshAt;
  bool _isDisposed = false;
  bool _isProcessingPersistedWork = false;
  Completer<void>? _persistedWorkCompleter;
  ErpNextSession? _activeErpNextSession;
  String? _queuedPhoneNumber;
  String? _activePhoneNumber;
  String? _activeRecordingPath;
  bool _isFetchingAllRecordings = false;
  bool _isUploadingAllRecordings = false;
  bool _isLoadingCustomers = false;
  bool _isRecordingPlaying = false;
  bool _isDarkMode = false;
  int _notificationBatchDepth = 0;
  bool _hasBatchedNotification = false;
  int _customerLoadGeneration = 0;
  String? _lastAutomaticRecordingCustomerSignature;
  String? _customerLoadError;
  String? _lastRecordingUploadError;

  void initializePlaybackEvents() {
    ServiceStarter.configurePlaybackEvents(
      onCompleted: _handlePlaybackEnded,
      onFailed: _handlePlaybackEnded,
    );
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    _completedPaymentEntryIds
      ..clear()
      ..addAll(prefs.getStringList(_completedPaymentEntriesKey) ?? const []);
    _restoreCallSessionLedger(prefs);
    await _discardUnlinkedSessions();
    await _migratePersistedCallTimestampsIntoLedger(prefs);
    await _pruneExpiredSessionHistory(notify: false);

    for (var i = 0; i < _customers.length; i++) {
      _customers[i] = _withPersistedCallTimestamps(_customers[i], prefs);
    }

    _notifyListeners();
  }

  void _restoreCallSessionLedger(SharedPreferences prefs) {
    _callSessions.clear();
    final encoded = prefs.getString(_callSessionLedgerKey);
    if (encoded == null || encoded.isEmpty) return;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;
      _callSessions.addAll(
        decoded
            .whereType<Map>()
            .map(
              (value) => PersistedCallSession.fromJson(
                Map<String, dynamic>.from(value),
              ),
            )
            .where(
              (session) =>
                  session.id.isNotEmpty && session.phoneNumber.isNotEmpty,
            ),
      );
      _callSessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    } catch (error) {
      debugPrint('CALL_SESSIONS: could not restore ledger: $error');
    }
  }

  Future<void> _persistCallSessionLedger() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _callSessionLedgerKey,
      jsonEncode(
        _callSessions
            .map((session) => session.toJson())
            .toList(growable: false),
      ),
    );
  }

  Future<void> _discardUnlinkedSessions() async {
    final previousLength = _callSessions.length;
    _callSessions.removeWhere(
      (session) => session.customerId?.trim().isNotEmpty != true,
    );
    if (_callSessions.length != previousLength) {
      await _persistCallSessionLedger();
    }
  }

  Future<void> _migratePersistedCallTimestampsIntoLedger(
    SharedPreferences prefs,
  ) async {
    var changed = false;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_draftCustomerCachePrefix)) continue;
      final encoded = prefs.getString(key);
      if (encoded == null || encoded.isEmpty) continue;

      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! List) continue;
        for (final rawCustomer in decoded.whereType<Map>()) {
          final customer = Map<String, dynamic>.from(rawCustomer);
          final phoneNumber = customer['phone_number']?.toString() ?? '';
          final normalizedPhone = _normalize(phoneNumber);
          if (normalizedPhone == null) continue;
          final startedAtMillis = prefs.getInt(_startedAtKey(normalizedPhone));
          if (startedAtMillis == null) continue;
          final startedAt = DateTime.fromMillisecondsSinceEpoch(
            startedAtMillis,
          );
          final draftCreatedAt = DateTime.tryParse(
            customer['latest_payment_entry_created_at']?.toString() ?? '',
          );
          if (draftCreatedAt != null && startedAt.isBefore(draftCreatedAt)) {
            continue;
          }
          final alreadySaved = _callSessions.any(
            (session) =>
                _normalize(session.phoneNumber) == normalizedPhone &&
                session.startedAt.difference(startedAt).abs() <=
                    _duplicateCallTolerance,
          );
          if (alreadySaved) continue;

          final endedAtMillis = prefs.getInt(_endedAtKey(normalizedPhone));
          final phoneId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
          _callSessions.add(
            PersistedCallSession(
              id: 'call_${phoneId}_${startedAt.millisecondsSinceEpoch}',
              customerId: customer['customer_id']?.toString(),
              customerName:
                  customer['customer_name']?.toString() ?? phoneNumber,
              phoneNumber: phoneNumber,
              paymentEntryIds:
                  (customer['payment_entry_ids'] as List?)
                      ?.map((value) => value.toString())
                      .toList(growable: false) ??
                  const [],
              draftCreatedAt: draftCreatedAt,
              startedAt: startedAt,
              endedAt: endedAtMillis == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(endedAtMillis),
              recordingPath: null,
              recordingName: null,
              recordingModifiedAt: null,
              status: PersistedCallStatus.waitingForRecording,
              lastError: null,
            ),
          );
          changed = true;
        }
      } catch (error) {
        debugPrint('CALL_SESSIONS: could not migrate $key: $error');
      }
    }

    if (changed) {
      _callSessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      await _persistCallSessionLedger();
    }
  }

  int _callSessionIndex(String sessionId) =>
      _callSessions.indexWhere((session) => session.id == sessionId);

  Future<void> _replaceCallSession(PersistedCallSession session) async {
    final index = _callSessionIndex(session.id);
    if (index == -1) {
      _callSessions.add(session);
    } else {
      _callSessions[index] = session;
    }
    _callSessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    await _persistCallSessionLedger();
    _notifyListeners();
  }

  Future<void> _setCallSessionUploadStatus(
    String sessionId,
    PersistedCallStatus status, {
    String? error,
  }) async {
    final index = _callSessionIndex(sessionId);
    if (index == -1) return;
    await _replaceCallSession(
      _callSessions[index].copyWith(
        status: status,
        statusChangedAt: _now(),
        lastError: error,
        clearError: error == null,
      ),
    );
  }

  bool _isResolvedSession(PersistedCallSession session) =>
      session.status == PersistedCallStatus.recordingNotFound ||
      session.status == PersistedCallStatus.uploaded;

  bool _isLinkedSession(PersistedCallSession session) =>
      session.customerId?.trim().isNotEmpty == true;

  Future<int> _removeResolvedSessions(
    bool Function(PersistedCallSession session) shouldRemove, {
    bool notify = true,
  }) async {
    final removable = _callSessions
        .where(
          (session) => _isResolvedSession(session) && shouldRemove(session),
        )
        .toList(growable: false);
    if (removable.isEmpty) return 0;

    await _callPersistence.deleteCalls(
      removable.map((session) => session.id),
      audioPaths: removable
          .map((session) => session.recordingPath)
          .whereType<String>(),
    );
    final removableIds = removable.map((session) => session.id).toSet();
    _callSessions.removeWhere((session) => removableIds.contains(session.id));
    await _persistCallSessionLedger();
    if (notify) _notifyListeners();
    return removable.length;
  }

  Future<int> _pruneExpiredSessionHistory({bool notify = true}) {
    final cutoff = _now().subtract(_sessionHistoryRetention);
    return _removeResolvedSessions(
      (session) => session.statusChangedAt.isBefore(cutoff),
      notify: notify,
    );
  }

  Future<int> clearResolvedSessionHistory() {
    return _removeResolvedSessions((_) => true);
  }

  Future<bool> deleteResolvedSession(String sessionId) async {
    final index = _callSessionIndex(sessionId);
    if (index == -1 || !_isResolvedSession(_callSessions[index])) return false;
    return await _removeResolvedSessions(
          (session) => session.id == sessionId,
        ) ==
        1;
  }

  Future<bool> rescanSession(String sessionId) async {
    final index = _callSessionIndex(sessionId);
    if (index == -1) return false;

    var session = _callSessions[index];
    if (session.status != PersistedCallStatus.waitingForRecording &&
        session.status != PersistedCallStatus.recordingNotFound) {
      return session.recording != null;
    }

    final claimedPaths = _callSessions
        .where((candidate) => candidate.id != session.id)
        .map((candidate) => candidate.recordingPath)
        .whereType<String>()
        .toSet();
    final recordings = await ServiceStarter.findRecordingsForPhone(
      session.phoneNumber,
    );
    final recording = _recordingForPersistedSession(
      session,
      recordings.where(
        (candidate) => !claimedPaths.contains(candidate.filePath),
      ),
    );
    if (recording == null) return false;

    session = session.copyWith(
      endedAt: session.endedAt ?? recording.lastModifiedTime,
      recording: recording,
      status: PersistedCallStatus.pendingUpload,
      statusChangedAt: _now(),
      clearError: true,
    );
    await _replaceCallSession(session);
    if (_activeErpNextSession != null && _wasDisconnected != true) {
      await _processPersistedSession(session);
    }
    return true;
  }

  Future<void> refreshPendingSessions() => _processPersistedWork();

  List<CustomerContact> get customers => List.unmodifiable(_customers);
  List<PersistedCallSession> get callSessions =>
      List.unmodifiable(_callSessions.reversed.where(_isLinkedSession));
  List<PersistedCallSession> get activeCallSessions => List.unmodifiable(
    _callSessions.reversed.where(
      (session) =>
          _isLinkedSession(session) &&
          (session.status == PersistedCallStatus.waitingForRecording ||
              session.status == PersistedCallStatus.pendingUpload),
    ),
  );
  List<PersistedCallSession> get sessionHistory => List.unmodifiable(
    _callSessions.reversed.where(
      (session) =>
          _isLinkedSession(session) &&
          (session.status == PersistedCallStatus.recordingNotFound ||
              session.status == PersistedCallStatus.uploaded),
    ),
  );
  List<CustomerContact> get customersToCall => List.unmodifiable(
    _customers.where((customer) => !_hasUploadedCall(customer)),
  );
  ErpNextSession? get activeErpNextSession => _activeErpNextSession;
  bool get isFetchingAllRecordings => _isFetchingAllRecordings;
  bool get isUploadingAllRecordings => _isUploadingAllRecordings;
  bool get isLoadingCustomers => _isLoadingCustomers;
  String? get customerLoadError => _customerLoadError;
  String? get lastRecordingUploadError => _lastRecordingUploadError;
  bool get isDarkMode => _isDarkMode;
  bool get canImportTestRecording =>
      _normalize(_testRecordingPhoneNumber) != null;
  String get testRecordingPhoneNumber => _testRecordingPhoneNumber;

  Future<void> setDarkMode(bool enabled) async {
    if (_isDarkMode == enabled) return;

    final previousValue = _isDarkMode;
    _isDarkMode = enabled;
    _notifyListeners();

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_darkModeKey, enabled);
    } catch (_) {
      _isDarkMode = previousValue;
      _notifyListeners();
      rethrow;
    }
  }

  int get recordingsReadyCount =>
      _customers.where((customer) => customer.latestRecording != null).length;

  int get matchedRecordingsCount => {
    ..._matchedRecordingTargets.map((target) => target.recording.filePath),
    ..._callSessions
        .where(_isLinkedSession)
        .map((session) => session.recordingPath)
        .whereType<String>(),
  }.length;

  int get pendingRecordingUploadsCount => {
    ..._matchedRecordingTargets
        .where(
          (target) =>
              recordingUploadState(target.recording) !=
              RecordingUploadState.uploaded,
        )
        .map((target) => target.recording.filePath),
    ..._callSessions
        .where(
          (session) =>
              _isLinkedSession(session) &&
              session.status == PersistedCallStatus.pendingUpload &&
              session.recordingPath != null,
        )
        .map((session) => session.recordingPath!),
  }.length;

  void clearErpNextSession() {
    _cancelAllAutomaticUploadRetries();
    _draftCustomerRefreshTimer?.cancel();
    _draftCustomerRefreshTimer = null;
    _persistedWorkTimer?.cancel();
    _persistedWorkTimer = null;
    _customerLoadGeneration++;
    _activeErpNextSession = null;
    _customers.clear();
    _queuedPhoneNumber = null;
    _activePhoneNumber = null;
    _activeRecordingPath = null;
    _recordingUploadStates.clear();
    _isFetchingAllRecordings = false;
    _isUploadingAllRecordings = false;
    _isLoadingCustomers = false;
    _isRecordingPlaying = false;
    _customerLoadError = null;
    _lastRecordingUploadError = null;
    _lastAutomaticRecordingCustomerSignature = null;
    _lastDraftCustomerRefreshAt = null;
    _notifyListeners();
  }

  bool isActiveRecording(CallRecordingFile recording) =>
      _activeRecordingPath == recording.filePath;

  bool isPlayingRecording(CallRecordingFile recording) =>
      isActiveRecording(recording) && _isRecordingPlaying;

  RecordingUploadState recordingUploadState(CallRecordingFile recording) =>
      _recordingUploadStates[recording.filePath] ??
      RecordingUploadState.pending;

  bool _hasUploadedCall(CustomerContact customer) {
    if (customer.paymentEntryIds.isNotEmpty &&
        customer.paymentEntryIds.every(_completedPaymentEntryIds.contains)) {
      return true;
    }

    final recordings = customer.availableRecordings.isEmpty
        ? [if (customer.latestRecording != null) customer.latestRecording!]
        : customer.availableRecordings;
    return recordings.isNotEmpty &&
        recordings.every(
          (recording) =>
              recordingUploadState(recording) == RecordingUploadState.uploaded,
        );
  }

  void _notifyListeners() {
    if (_isDisposed) return;
    if (_notificationBatchDepth > 0) {
      _hasBatchedNotification = true;
      return;
    }

    notifyListeners();
  }

  Future<T> _batchNotifications<T>(Future<T> Function() action) async {
    _notificationBatchDepth++;
    try {
      return await action();
    } finally {
      _notificationBatchDepth--;
      if (_notificationBatchDepth == 0 && _hasBatchedNotification) {
        _hasBatchedNotification = false;
        _notifyListeners();
      }
    }
  }

  Future<RecordingBatchUploadResult> uploadAllRecordings() async {
    final persistedPending = _callSessions
        .where(
          (session) =>
              _isLinkedSession(session) &&
              session.status == PersistedCallStatus.pendingUpload &&
              session.recording != null,
        )
        .toList(growable: false);
    final persistedPaths = persistedPending
        .map((session) => session.recordingPath)
        .whereType<String>()
        .toSet();
    final targets = _matchedRecordingTargets
        .where((target) => !persistedPaths.contains(target.recording.filePath))
        .toList(growable: false);
    final total = persistedPending.length + targets.length;
    if (_isUploadingAllRecordings) {
      return RecordingBatchUploadResult(
        total: total,
        attempted: 0,
        uploaded: 0,
        failed: 0,
        alreadyUploaded: targets
            .where(
              (target) =>
                  recordingUploadState(target.recording) ==
                  RecordingUploadState.uploaded,
            )
            .length,
      );
    }

    _isUploadingAllRecordings = true;
    _lastRecordingUploadError = null;
    _notifyListeners();

    var attempted = 0;
    var uploaded = 0;
    var failed = 0;
    var alreadyUploaded = 0;

    try {
      for (final session in persistedPending) {
        attempted++;
        await _processPersistedSession(session);
        final index = _callSessionIndex(session.id);
        if (index != -1 &&
            _callSessions[index].status == PersistedCallStatus.uploaded) {
          uploaded++;
        } else {
          failed++;
        }
      }

      for (final target in targets) {
        if (recordingUploadState(target.recording) ==
            RecordingUploadState.uploaded) {
          alreadyUploaded++;
          continue;
        }

        final call = await _saveMatchedRecording(
          customer: target.customer,
          recording: target.recording,
        );
        if (call == null) {
          failed++;
          continue;
        }

        if (recordingUploadState(target.recording) ==
            RecordingUploadState.uploaded) {
          alreadyUploaded++;
          continue;
        }

        attempted++;
        final didUpload = await _uploadMatchedRecording(
          customer: target.customer,
          recording: target.recording,
          call: call,
        );
        if (didUpload) {
          uploaded++;
        } else {
          failed++;
        }
      }

      return RecordingBatchUploadResult(
        total: total,
        attempted: attempted,
        uploaded: uploaded,
        failed: failed,
        alreadyUploaded: alreadyUploaded,
      );
    } finally {
      _isUploadingAllRecordings = false;
      _notifyListeners();
    }
  }

  Future<int> loadDraftPaymentCustomers(ErpNextSession session) async {
    if (_isLoadingCustomers) return _customers.length;

    final loadGeneration = ++_customerLoadGeneration;
    _activeErpNextSession = session;
    _startDraftCustomerRefreshTimer();
    _startPersistedWorkTimer();
    if (_customers.isEmpty) {
      await _restoreCachedDraftPaymentCustomers(session);
    }
    _isLoadingCustomers = true;
    _customerLoadError = null;
    _notifyListeners();

    try {
      final remoteCustomers = await _customerSource.fetchDraftPaymentCustomers(
        session,
      );
      if (loadGeneration != _customerLoadGeneration) {
        return _customers.length;
      }

      final prefs = await SharedPreferences.getInstance();
      if (loadGeneration != _customerLoadGeneration) {
        return _customers.length;
      }
      _replaceDraftPaymentCustomers(remoteCustomers, session, prefs);
      await _cacheDraftPaymentCustomers(remoteCustomers, session, prefs);
      _lastDraftCustomerRefreshAt = DateTime.now();
      unawaited(_processPersistedWork());
      unawaited(reconcileCompletedBackgroundCalls());
      _scheduleAutomaticRecordingFetch();
      return _customers.length;
    } on ErpNextCustomerFetchException catch (error) {
      if (loadGeneration != _customerLoadGeneration) {
        return _customers.length;
      }
      _customerLoadError = error.message;
      return _customers.length;
    } catch (_) {
      if (loadGeneration != _customerLoadGeneration) {
        return _customers.length;
      }
      _customerLoadError =
          'Could not refresh draft-payment customers from ERPNext.';
      return _customers.length;
    } finally {
      if (loadGeneration == _customerLoadGeneration) {
        _isLoadingCustomers = false;
        _notifyListeners();
      }
    }
  }

  Future<int> refreshDraftPaymentCustomers() async {
    final session = _activeErpNextSession;
    if (session == null) {
      _customerLoadError = 'Log in to ERPNext before refreshing customers.';
      _notifyListeners();
      return _customers.length;
    }
    return loadDraftPaymentCustomers(session);
  }

  Future<int> refreshDraftPaymentCustomersIfStale() async {
    final lastRefresh = _lastDraftCustomerRefreshAt;
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) <
            _draftCustomerRefreshInterval) {
      return _customers.length;
    }
    return refreshDraftPaymentCustomers();
  }

  void _startDraftCustomerRefreshTimer() {
    if (!_automaticDraftCustomerRefreshEnabled || _isDisposed) return;
    _draftCustomerRefreshTimer?.cancel();
    _draftCustomerRefreshTimer = Timer.periodic(
      _draftCustomerRefreshInterval,
      (_) => unawaited(refreshDraftPaymentCustomers()),
    );
  }

  void _startPersistedWorkTimer() {
    if (!_automaticPersistedWorkEnabled || _isDisposed) return;
    _persistedWorkTimer?.cancel();
    _persistedWorkTimer = Timer.periodic(
      _persistedWorkInterval,
      (_) => unawaited(_processPersistedWork()),
    );
  }

  Future<void> _processPersistedWork() async {
    if (_activeErpNextSession == null || _wasDisconnected == true) {
      return;
    }

    if (_isProcessingPersistedWork) {
      await _persistedWorkCompleter?.future;
      return _processPersistedWork();
    }

    _isProcessingPersistedWork = true;
    final workCompleter = Completer<void>();
    _persistedWorkCompleter = workCompleter;
    try {
      await _pruneExpiredSessionHistory();
      final snapshot = _callSessions
          .where(_isLinkedSession)
          .toList(growable: false);
      final claimedPaths = snapshot
          .map((session) => session.recordingPath)
          .whereType<String>()
          .toSet();

      for (var session in snapshot) {
        if (session.status == PersistedCallStatus.uploaded ||
            session.status == PersistedCallStatus.recordingNotFound) {
          continue;
        }

        if (session.recording == null) {
          final recordings = await ServiceStarter.findRecordingsForPhone(
            session.phoneNumber,
          );
          final recording = _recordingForPersistedSession(
            session,
            recordings.where(
              (candidate) => !claimedPaths.contains(candidate.filePath),
            ),
          );
          if (recording == null) {
            final discoveryStartedAt = session.endedAt ?? session.startedAt;
            final discoveryExpired = !_now().isBefore(
              discoveryStartedAt.add(_recordingDiscoveryTimeout),
            );
            if (discoveryExpired) {
              await _replaceCallSession(
                session.copyWith(
                  status: PersistedCallStatus.recordingNotFound,
                  statusChangedAt: _now(),
                  lastError:
                      'No matching phone recording was found during automatic discovery.',
                ),
              );
            }
            continue;
          }

          claimedPaths.add(recording.filePath);
          session = session.copyWith(
            endedAt: session.endedAt ?? recording.lastModifiedTime,
            recording: recording,
            status: PersistedCallStatus.pendingUpload,
            statusChangedAt: _now(),
            clearError: true,
          );
          await _replaceCallSession(session);
        }

        await _processPersistedSession(session);
      }
    } finally {
      _isProcessingPersistedWork = false;
      if (!workCompleter.isCompleted) workCompleter.complete();
      if (identical(_persistedWorkCompleter, workCompleter)) {
        _persistedWorkCompleter = null;
      }
    }
  }

  CallRecordingFile? _recordingForPersistedSession(
    PersistedCallSession session,
    Iterable<CallRecordingFile> recordings,
  ) {
    final minuteStart = DateTime(
      session.startedAt.year,
      session.startedAt.month,
      session.startedAt.day,
      session.startedAt.hour,
      session.startedAt.minute,
    ).subtract(_recordingWindowStartOffset);
    final minuteEnd = minuteStart.add(_recordingWindowDuration);
    final matches =
        recordings.where((recording) {
          return _timestampInWindow(
                recording.effectiveTimestamp,
                minuteStart,
                minuteEnd,
              ) ||
              _timestampInWindow(
                recording.lastModifiedTime,
                minuteStart,
                minuteEnd,
              );
        }).toList()..sort((a, b) {
          final aDelta = a.effectiveTimestamp
              .difference(session.startedAt)
              .inSeconds
              .abs();
          final bDelta = b.effectiveTimestamp
              .difference(session.startedAt)
              .inSeconds
              .abs();
          return aDelta.compareTo(bDelta);
        });
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _processPersistedSession(PersistedCallSession session) async {
    final recording = session.recording;
    if (recording == null || session.customerId?.isNotEmpty != true) return;

    final customer = CustomerContact(
      erpNextCustomerId: session.customerId,
      name: session.customerName,
      phoneNumber: session.phoneNumber,
      paymentEntryIds: session.paymentEntryIds,
      latestPaymentEntryCreatedAt: session.draftCreatedAt,
      subtitle: 'Saved call session',
      statusLabel: 'Recording saved; upload pending',
      lastCallStartedAt: session.startedAt,
      lastCallEndedAt: session.endedAt,
      latestRecording: recording,
      availableRecordings: [recording],
      matchingRecordingsCount: 1,
    );
    final call = await _saveMatchedRecording(
      customer: customer,
      recording: recording,
      persistedSession: session,
    );
    if (call == null ||
        recordingUploadState(recording) == RecordingUploadState.uploaded) {
      return;
    }
    await _uploadMatchedRecording(
      customer: customer,
      recording: recording,
      call: call,
    );
  }

  String _draftCustomerCacheKey(ErpNextSession session) {
    final encodedUser = base64Url.encode(
      utf8.encode(session.userId.trim().toLowerCase()),
    );
    return '$_draftCustomerCachePrefix$encodedUser';
  }

  Future<void> _restoreCachedDraftPaymentCustomers(
    ErpNextSession session,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_draftCustomerCacheKey(session));
      if (rawCache == null || rawCache.isEmpty) return;
      final decoded = jsonDecode(rawCache);
      if (decoded is! List) return;

      final cachedCustomers = decoded
          .whereType<Map>()
          .map((rawCustomer) {
            final customer = Map<String, dynamic>.from(rawCustomer);
            return DraftPaymentCustomer(
              customerId: customer['customer_id']?.toString() ?? '',
              customerName: customer['customer_name']?.toString() ?? '',
              phoneNumber: customer['phone_number']?.toString() ?? '',
              imageUrl: customer['image_url']?.toString(),
              draftPaymentCount:
                  (customer['draft_payment_count'] as num?)?.toInt() ?? 0,
              paymentEntryIds:
                  (customer['payment_entry_ids'] as List?)
                      ?.map((id) => id.toString())
                      .toList(growable: false) ??
                  const [],
              latestPaymentEntryCreatedAt: DateTime.tryParse(
                customer['latest_payment_entry_created_at']?.toString() ?? '',
              ),
            );
          })
          .where(
            (customer) =>
                customer.customerId.isNotEmpty &&
                customer.phoneNumber.isNotEmpty,
          )
          .toList(growable: false);
      if (cachedCustomers.isEmpty) return;

      _replaceDraftPaymentCustomers(cachedCustomers, session, prefs);
      unawaited(_processPersistedWork());
      debugPrint(
        'DRAFT_CUSTOMERS: restored ${cachedCustomers.length} cached customer(s)',
      );
      _notifyListeners();
      _scheduleAutomaticRecordingFetch();
    } catch (error) {
      debugPrint('DRAFT_CUSTOMERS: could not restore cache: $error');
    }
  }

  Future<void> _cacheDraftPaymentCustomers(
    List<DraftPaymentCustomer> customers,
    ErpNextSession session,
    SharedPreferences prefs,
  ) async {
    try {
      final encoded = customers
          .map(
            (customer) => {
              'customer_id': customer.customerId,
              'customer_name': customer.customerName,
              'phone_number': customer.phoneNumber,
              'image_url': customer.imageUrl,
              'draft_payment_count': customer.draftPaymentCount,
              'payment_entry_ids': customer.paymentEntryIds,
              'latest_payment_entry_created_at': customer
                  .latestPaymentEntryCreatedAt
                  ?.toIso8601String(),
            },
          )
          .toList(growable: false);
      await prefs.setString(
        _draftCustomerCacheKey(session),
        jsonEncode(encoded),
      );
    } catch (error) {
      debugPrint('DRAFT_CUSTOMERS: could not update cache: $error');
    }
  }

  void _replaceDraftPaymentCustomers(
    List<DraftPaymentCustomer> remoteCustomers,
    ErpNextSession session,
    SharedPreferences prefs,
  ) {
    _completedPaymentEntryIds
      ..clear()
      ..addAll(prefs.getStringList(_completedPaymentEntriesKey) ?? const []);
    final refreshedCustomers = <CustomerContact>[];

    for (final remoteCustomer in remoteCustomers) {
      final pendingPaymentEntryIds = remoteCustomer.paymentEntryIds
          .where((id) => !_completedPaymentEntryIds.contains(id))
          .toList(growable: false);
      final visibleDraftPaymentCount = remoteCustomer.paymentEntryIds.isEmpty
          ? remoteCustomer.draftPaymentCount
          : pendingPaymentEntryIds.length;
      final previous =
          _customerForErpNextId(remoteCustomer.customerId) ??
          _customerForPhone(remoteCustomer.phoneNumber);
      final draftCreatedAt = remoteCustomer.latestPaymentEntryCreatedAt;
      final previousCallStartedAt = previous?.lastCallStartedAt;
      final hasCallForCurrentDraft =
          previousCallStartedAt != null &&
          (draftCreatedAt == null ||
              !previousCallStartedAt.isBefore(draftCreatedAt));
      final draftLabel = visibleDraftPaymentCount == 1
          ? '1 draft payment entry'
          : '$visibleDraftPaymentCount draft payment entries';
      final refreshed = CustomerContact(
        erpNextCustomerId: remoteCustomer.customerId,
        name: remoteCustomer.customerName,
        phoneNumber: remoteCustomer.phoneNumber,
        profileImageUrl: remoteCustomer.imageUrl,
        profileImageHeaders: _authenticatedImageHeaders(
          imageUrl: remoteCustomer.imageUrl,
          session: session,
        ),
        draftPaymentCount: visibleDraftPaymentCount,
        paymentEntryIds: remoteCustomer.paymentEntryIds,
        latestPaymentEntryCreatedAt: remoteCustomer.latestPaymentEntryCreatedAt,
        subtitle: draftLabel,
        statusLabel: hasCallForCurrentDraft
            ? previous!.statusLabel
            : 'Ready to call',
        lastCallStartedAt: hasCallForCurrentDraft
            ? previousCallStartedAt
            : null,
        lastCallEndedAt: hasCallForCurrentDraft
            ? previous!.lastCallEndedAt
            : null,
        latestRecording: hasCallForCurrentDraft
            ? previous!.latestRecording
            : null,
        availableRecordings: hasCallForCurrentDraft
            ? previous!.availableRecordings
            : const [],
        matchingRecordingsCount: hasCallForCurrentDraft
            ? previous!.matchingRecordingsCount
            : 0,
        isCallQueued: hasCallForCurrentDraft ? previous!.isCallQueued : false,
        isCallInProgress: hasCallForCurrentDraft
            ? previous!.isCallInProgress
            : false,
      );
      refreshedCustomers.add(_withPersistedCallTimestamps(refreshed, prefs));
    }

    _customers
      ..clear()
      ..addAll(refreshedCustomers);
    _enrichCallSessionsFromCustomers();
  }

  void _enrichCallSessionsFromCustomers() {
    var changed = false;
    for (var index = 0; index < _callSessions.length; index++) {
      final session = _callSessions[index];
      final customer = _customerForPhone(session.phoneNumber);
      if (customer == null ||
          (session.customerId?.isNotEmpty == true &&
              session.customerName != session.phoneNumber)) {
        continue;
      }
      _callSessions[index] = session.copyWith(
        customerId: customer.erpNextCustomerId,
        customerName: customer.name,
        paymentEntryIds: customer.paymentEntryIds,
        draftCreatedAt: customer.latestPaymentEntryCreatedAt,
      );
      changed = true;
    }
    if (changed) unawaited(_persistCallSessionLedger());
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

  Future<void> reconcileCompletedBackgroundCalls() async {
    final completedCalls = await ServiceStarter.consumeCompletedCalls();
    for (final completedCall in completedCalls) {
      final phoneNumber = completedCall.phoneNumber;
      if (phoneNumber == null || phoneNumber.trim().isEmpty) continue;

      await markCallStarted(phoneNumber, startedAt: completedCall.startedAt);
      await markCallCompleted(
        phoneNumber: phoneNumber,
        callEndedAt: completedCall.endedAt,
        recording: completedCall.recording,
      );
    }
  }

  Future<void> markCallStarted(
    String? phoneNumber, {
    required DateTime startedAt,
  }) async {
    final resolvedNumber = _resolvePhoneNumber(phoneNumber);
    if (resolvedNumber == null) return;

    final customer = _customerForPhone(resolvedNumber);
    if (customer != null) {
      final normalizedPhone = _normalize(resolvedNumber) ?? resolvedNumber;
      PersistedCallSession? existing;
      for (final session in _callSessions.reversed) {
        if (_normalize(session.phoneNumber) == normalizedPhone &&
            session.startedAt.difference(startedAt).abs() <=
                _duplicateCallTolerance) {
          existing = session;
          break;
        }
      }
      if (existing == null) {
        final phoneId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        await _replaceCallSession(
          PersistedCallSession(
            id: 'call_${phoneId}_${startedAt.millisecondsSinceEpoch}',
            customerId: customer.erpNextCustomerId,
            customerName: customer.name,
            phoneNumber: customer.phoneNumber,
            paymentEntryIds: customer.paymentEntryIds,
            draftCreatedAt: customer.latestPaymentEntryCreatedAt,
            startedAt: startedAt,
            endedAt: null,
            recordingPath: null,
            recordingName: null,
            recordingModifiedAt: null,
            status: PersistedCallStatus.waitingForRecording,
            lastError: null,
          ),
        );
      }
    }

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
    await _persistCallTimestamps(
      phoneNumber: resolvedNumber,
      startedAt: startedAt,
    );
  }

  Future<void> markCallCompleted({
    String? phoneNumber,
    required DateTime callEndedAt,
    CallRecordingFile? recording,
  }) async {
    final ledgerSession = _latestCallSessionForPhone(phoneNumber);
    final resolvedNumber =
        _resolvePhoneNumber(phoneNumber) ?? ledgerSession?.phoneNumber;
    if (resolvedNumber == null) return;

    final existingCustomer = _customerForPhone(resolvedNumber);
    final existingRecording = existingCustomer?.latestRecording;
    if (recording != null &&
        existingRecording != null &&
        _timestampsAreClose(
          existingCustomer?.lastCallEndedAt,
          callEndedAt,
          _duplicateCallTolerance,
        )) {
      _updateCustomer(
        resolvedNumber,
        (current) => current.copyWith(
          statusLabel: switch (recordingUploadState(existingRecording)) {
            RecordingUploadState.uploaded => 'Recording uploaded',
            RecordingUploadState.uploading => 'Uploading recording...',
            _ => 'Recording saved; upload pending',
          },
          isCallQueued: false,
          isCallInProgress: false,
        ),
      );
      _queuedPhoneNumber = null;
      _activePhoneNumber = null;
      return;
    }

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

    PersistedCallSession? updatedLedgerSession;
    if (ledgerSession != null) {
      updatedLedgerSession = ledgerSession.copyWith(
        endedAt: callEndedAt,
        recording: recording,
        status: recording == null
            ? PersistedCallStatus.waitingForRecording
            : PersistedCallStatus.pendingUpload,
        clearError: true,
      );
      await _replaceCallSession(updatedLedgerSession);
    }

    if (recording != null) {
      final customer = _customerForPhone(resolvedNumber);
      if (customer != null) {
        final call = await _saveMatchedRecording(
          customer: customer,
          recording: recording,
        );
        if (call != null &&
            recordingUploadState(recording) != RecordingUploadState.uploaded) {
          _updateCustomer(
            resolvedNumber,
            (current) =>
                current.copyWith(statusLabel: 'Uploading recording...'),
          );
          final uploaded = await _uploadMatchedRecording(
            customer: customer,
            recording: recording,
            call: call,
          );
          _updateCustomer(
            resolvedNumber,
            (current) => current.copyWith(
              statusLabel: uploaded
                  ? 'Recording uploaded'
                  : 'Recording saved; upload pending',
            ),
          );
        }
      } else if (updatedLedgerSession != null) {
        await _processPersistedSession(updatedLedgerSession);
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
        _notifyListeners();
      }
      return didPause;
    }

    if (isCurrentRecording) {
      final didResume = await ServiceStarter.resumeRecording();
      if (didResume) {
        _isRecordingPlaying = true;
        _notifyListeners();
      }
      return didResume;
    }

    final didStart = await ServiceStarter.playRecording(recording.filePath);
    if (didStart) {
      _activeRecordingPath = recording.filePath;
      _isRecordingPlaying = true;
      _notifyListeners();
    }
    return didStart;
  }

  Future<int> fetchRecordingsForAllCustomers({bool silent = false}) async {
    if (_isFetchingAllRecordings) return recordingsReadyCount;

    if (!silent) {
      _isFetchingAllRecordings = true;
      _notifyListeners();
    }

    Future<int> scanCustomers() async {
      var matchedCustomers = 0;
      final customerSnapshot = List<CustomerContact>.from(_customers);

      for (final customer in customerSnapshot) {
        if (!silent) {
          _updateCustomer(
            customer.phoneNumber,
            (current) => current.copyWith(
              statusLabel: 'Checking saved recordings...',
              isCallQueued: false,
              isCallInProgress: false,
            ),
          );
        }

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
        var uploadFailed = false;
        if (latestRecording != null) {
          matchedCustomers++;
          final call = await _saveMatchedRecording(
            customer: currentCustomer,
            recording: latestRecording,
          );
          if (call != null &&
              recordingUploadState(latestRecording) !=
                  RecordingUploadState.uploaded) {
            final uploaded = await _uploadMatchedRecording(
              customer: currentCustomer,
              recording: latestRecording,
              call: call,
            );
            uploadFailed = !uploaded;
          }
        }

        _updateCustomer(customer.phoneNumber, (current) {
          final inferredStartedAt = latestRecording == null
              ? null
              : _callStartForCurrentDraft(current) ??
                    latestRecording.effectiveTimestamp;
          return current.copyWith(
            statusLabel: latestRecording == null
                ? current.lastCallStartedAt == null
                      ? 'Ready to call'
                      : 'No recordings matched the last app call'
                : uploadFailed
                ? 'Recording saved; upload pending'
                : 'Recording uploaded',
            lastCallStartedAt: inferredStartedAt,
            lastCallEndedAt: latestRecording?.lastModifiedTime,
            latestRecording: latestRecording,
            availableRecordings: latestRecording == null
                ? const []
                : [latestRecording],
            matchingRecordingsCount: latestRecording == null ? 0 : 1,
            clearRecording: latestRecording == null,
            isCallQueued: false,
            isCallInProgress: false,
          );
        });
      }

      return matchedCustomers;
    }

    try {
      if (silent) {
        return await _batchNotifications(scanCustomers);
      }

      return await scanCustomers();
    } finally {
      if (!silent) {
        _isFetchingAllRecordings = false;
        _notifyListeners();
      }
    }
  }

  void _scheduleAutomaticRecordingFetch() {
    if (_customers.isEmpty) return;
    final signature = _customers
        .map(
          (customer) =>
              '${customer.erpNextCustomerId}:'
              '${_normalize(customer.phoneNumber)}:'
              '${customer.latestPaymentEntryCreatedAt?.toIso8601String()}:'
              '${customer.paymentEntryIds.join(",")}',
        )
        .join('|');
    if (signature == _lastAutomaticRecordingCustomerSignature) return;

    _lastAutomaticRecordingCustomerSignature = signature;
    unawaited(
      Future<void>.microtask(() async {
        await fetchRecordingsForAllCustomers(silent: true);
      }),
    );
  }

  Future<bool> importLatestSavedRecordingForTest() async {
    final configuredPhone = _normalize(_testRecordingPhoneNumber);
    if (configuredPhone == null) return false;

    final customer = _customerForPhone(configuredPhone);
    if (customer == null) {
      _lastRecordingUploadError =
          'The configured test customer is not in the draft-payment list.';
      _notifyListeners();
      return false;
    }

    final recordings = await ServiceStarter.findRecordingsForPhone(
      customer.phoneNumber,
    );
    final directFileRecordings =
        recordings
            .where((recording) => !recording.filePath.startsWith('content://'))
            .toList(growable: false)
          ..sort(
            (a, b) => b.effectiveTimestamp.compareTo(a.effectiveTimestamp),
          );
    if (directFileRecordings.isEmpty) {
      _lastRecordingUploadError =
          'No saved phone recording matched ${customer.phoneNumber}.';
      _notifyListeners();
      return false;
    }

    // This path is enabled only in a test build. Give the historical file a
    // small synthetic call window so the normal pending/upload flow can be
    // exercised without placing another call.
    final recording = directFileRecordings.first;
    final endedAt = recording.effectiveTimestamp;
    final startedAt = endedAt.subtract(const Duration(minutes: 1));
    _updateCustomer(
      customer.phoneNumber,
      (current) => current.copyWith(
        statusLabel: 'Saved test recording ready',
        lastCallStartedAt: startedAt,
        lastCallEndedAt: endedAt,
        latestRecording: recording,
        availableRecordings: [recording],
        matchingRecordingsCount: 1,
        isCallQueued: false,
        isCallInProgress: false,
      ),
    );
    await _persistCallTimestamps(
      phoneNumber: customer.phoneNumber,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    final call = await _saveMatchedRecording(
      customer: customer,
      recording: recording,
    );
    if (call != null &&
        recordingUploadState(recording) != RecordingUploadState.uploaded) {
      final uploaded = await _uploadMatchedRecording(
        customer: customer,
        recording: recording,
        call: call,
      );
      _updateCustomer(
        customer.phoneNumber,
        (current) => current.copyWith(
          statusLabel: uploaded
              ? 'Recording uploaded'
              : 'Recording saved; upload pending',
        ),
      );
    }
    return true;
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
    _notifyListeners();
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

  PersistedCallSession? _latestCallSessionForPhone(String? phoneNumber) {
    final normalizedTarget = _normalize(phoneNumber);
    if (normalizedTarget == null) return null;

    PersistedCallSession? latest;
    for (final session in _callSessions) {
      if (_normalize(session.phoneNumber) != normalizedTarget) continue;
      if (latest == null || session.startedAt.isAfter(latest.startedAt)) {
        latest = session;
      }
    }
    return latest;
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
    final erpNextUri = Uri.tryParse(_erpNextBaseUrl);
    if (uri == null ||
        erpNextUri == null ||
        uri.scheme != erpNextUri.scheme ||
        uri.host != erpNextUri.host ||
        uri.port != erpNextUri.port) {
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

    final persistedStartedAt = startedAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(startedAtMillis);
    final draftCreatedAt = customer.latestPaymentEntryCreatedAt;
    if (persistedStartedAt != null &&
        draftCreatedAt != null &&
        persistedStartedAt.isBefore(draftCreatedAt)) {
      // A call from an older draft must not make an old recording eligible
      // when this customer receives a new draft Payment Entry.
      return customer;
    }

    return customer.copyWith(
      lastCallStartedAt: persistedStartedAt ?? customer.lastCallStartedAt,
      lastCallEndedAt: endedAtMillis == null
          ? customer.lastCallEndedAt
          : DateTime.fromMillisecondsSinceEpoch(endedAtMillis),
    );
  }

  List<CallRecordingFile> _recordingsMatchingCallWindow(
    CustomerContact customer,
    List<CallRecordingFile> recordings,
  ) {
    final callStartedAt = _callStartForCurrentDraft(customer);
    final draftCreatedAt = customer.latestPaymentEntryCreatedAt;

    if (callStartedAt == null) {
      if (draftCreatedAt == null) return const <CallRecordingFile>[];

      final matches =
          recordings
              .where(
                (recording) =>
                    !recording.effectiveTimestamp.isBefore(draftCreatedAt),
              )
              .toList()
            ..sort(
              (a, b) => b.effectiveTimestamp.compareTo(a.effectiveTimestamp),
            );
      return matches.take(1).toList(growable: false);
    }

    if (draftCreatedAt != null && callStartedAt.isBefore(draftCreatedAt)) {
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

    return matches.take(1).toList(growable: false);
  }

  DateTime? _callStartForCurrentDraft(CustomerContact customer) {
    final callStartedAt = customer.lastCallStartedAt;
    if (callStartedAt == null) return null;

    final draftCreatedAt = customer.latestPaymentEntryCreatedAt;
    if (draftCreatedAt != null && callStartedAt.isBefore(draftCreatedAt)) {
      return null;
    }
    return callStartedAt;
  }

  bool _timestampInWindow(DateTime timestamp, DateTime start, DateTime end) {
    return !timestamp.isBefore(start) && timestamp.isBefore(end);
  }

  bool _timestampsAreClose(
    DateTime? first,
    DateTime second,
    Duration tolerance,
  ) {
    if (first == null) return false;
    return first.difference(second).abs() <= tolerance;
  }

  String? _resolvePhoneNumber(String? rawPhoneNumber) {
    final normalized = _normalize(rawPhoneNumber);

    if (normalized != null &&
        (_customers.any(
              (customer) => _normalize(customer.phoneNumber) == normalized,
            ) ||
            _callSessions.any(
              (session) =>
                  _isLinkedSession(session) &&
                  _normalize(session.phoneNumber) == normalized &&
                  (session.status == PersistedCallStatus.waitingForRecording ||
                      session.status == PersistedCallStatus.pendingUpload),
            ))) {
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

  Future<CallModel?> _saveMatchedRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
    PersistedCallSession? persistedSession,
  }) async {
    final call = persistedSession == null
        ? _callForRecording(customer: customer, recording: recording)
        : _callForPersistedRecording(
            session: persistedSession,
            recording: recording,
          );
    if (call == null) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError =
          'The call start time is missing. This recording remains pending.';
      _notifyListeners();
      return null;
    }

    final ledgerIndex = _callSessionIndex(call.sessionId);
    final ledgerSession = ledgerIndex == -1
        ? PersistedCallSession(
            id: call.sessionId,
            customerId: customer.erpNextCustomerId,
            customerName: customer.name,
            phoneNumber: customer.phoneNumber,
            paymentEntryIds: customer.paymentEntryIds,
            draftCreatedAt: customer.latestPaymentEntryCreatedAt,
            startedAt: DateTime.parse(call.createdAt),
            endedAt: customer.lastCallEndedAt ?? recording.lastModifiedTime,
            recordingPath: recording.filePath,
            recordingName: recording.fileName,
            recordingModifiedAt: recording.lastModifiedTime,
            status: PersistedCallStatus.pendingUpload,
            lastError: null,
          )
        : _callSessions[ledgerIndex].copyWith(
            endedAt: customer.lastCallEndedAt ?? recording.lastModifiedTime,
            recording: recording,
            status: PersistedCallStatus.pendingUpload,
            clearError: true,
          );
    await _replaceCallSession(ledgerSession);

    final existingCall = await _callPersistence.getCall(call.sessionId);
    final normalizedPhone =
        _normalize(customer.phoneNumber) ?? customer.phoneNumber;
    final phoneId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final legacySessionId =
        'call_${phoneId}_${DateTime.parse(call.createdAt).millisecondsSinceEpoch}_${recording.lastModifiedTime.millisecondsSinceEpoch}';
    final legacyCall = legacySessionId == call.sessionId
        ? existingCall
        : await _callPersistence.getCall(legacySessionId);
    final existingRecordingCall = await _callPersistence.getCallByAudioPath(
      recording.filePath,
    );
    if (existingCall?['status'] == 'uploaded' ||
        legacyCall?['status'] == 'uploaded' ||
        existingRecordingCall?['status'] == 'uploaded') {
      await _markPaymentEntriesCompleted(customer);
      _recordingUploadStates[recording.filePath] =
          RecordingUploadState.uploaded;
      await _replaceCallSession(
        ledgerSession.copyWith(
          status: PersistedCallStatus.uploaded,
          clearError: true,
        ),
      );
      _lastRecordingUploadError = null;
      _notifyListeners();
      return call;
    }

    if (existingCall == null) {
      await _callPersistence.saveCall(call.toMap());
    }
    if (recordingUploadState(recording) != RecordingUploadState.failed) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.pending;
    }
    _notifyListeners();
    return call;
  }

  Future<bool> _uploadMatchedRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
    required CallModel call,
  }) async {
    if (recordingUploadState(recording) == RecordingUploadState.uploading) {
      return false;
    }

    if (!_recordingUploader.isConfigured) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError =
          'Recording upload is not configured. The recordings remain pending.';
      _notifyListeners();
      return false;
    }

    _recordingUploadStates[recording.filePath] = RecordingUploadState.uploading;
    _lastRecordingUploadError = null;
    _notifyListeners();

    try {
      debugPrint(
        'RECORDING_UPLOAD: starting upload '
        'session=${call.sessionId} customer=${customer.erpNextCustomerId} '
        'agent=${_activeErpNextSession?.userId ?? "(not logged in)"}',
      );
      await _recordingUploader.upload(
        call: call,
        customerId: customer.erpNextCustomerId,
        agentEmail: _activeErpNextSession?.userId,
      );
      await _callPersistence.updateStatus(call.sessionId, 'uploaded');
      await _markPaymentEntriesCompleted(customer);
      _recordingUploadStates[recording.filePath] =
          RecordingUploadState.uploaded;
      _clearAutomaticUploadRetry(recording.filePath);
      await _setCallSessionUploadStatus(
        call.sessionId,
        PersistedCallStatus.uploaded,
      );
      _lastRecordingUploadError = null;
      debugPrint('RECORDING_UPLOAD: uploaded session=${call.sessionId}');
      _notifyListeners();
      return true;
    } on RecordingUploadException catch (error) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError = error.message;
      await _setCallSessionUploadStatus(
        call.sessionId,
        PersistedCallStatus.pendingUpload,
        error: error.message,
      );
      debugPrint(
        'RECORDING_UPLOAD: failed session=${call.sessionId} '
        'reason=${error.message}',
      );
      _scheduleAutomaticUploadRetry(
        customer: customer,
        recording: recording,
        call: call,
      );
    } catch (_) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError =
          'Could not upload the recording. It remains pending.';
      await _setCallSessionUploadStatus(
        call.sessionId,
        PersistedCallStatus.pendingUpload,
        error: _lastRecordingUploadError,
      );
      debugPrint('RECORDING_UPLOAD: failed session=${call.sessionId}');
      _scheduleAutomaticUploadRetry(
        customer: customer,
        recording: recording,
        call: call,
      );
    }
    _notifyListeners();
    return false;
  }

  void _scheduleAutomaticUploadRetry({
    required CustomerContact customer,
    required CallRecordingFile recording,
    required CallModel call,
  }) {
    if (recordingUploadState(recording) == RecordingUploadState.uploaded ||
        _activeErpNextSession == null) {
      return;
    }

    final filePath = recording.filePath;
    final attempt = _automaticUploadRetryAttempts[filePath] ?? 0;
    final delayIndex = attempt < _automaticUploadRetryDelays.length
        ? attempt
        : _automaticUploadRetryDelays.length - 1;
    final delay = _automaticUploadRetryDelays[delayIndex];

    _pendingRecordingUploads[filePath] = _PendingRecordingUpload(
      customer: customer,
      recording: recording,
      call: call,
    );
    if (_wasDisconnected == true) {
      _cancelAutomaticUploadRetryTimer(filePath);
      debugPrint(
        'RECORDING_UPLOAD: offline; upload paused '
        'session=${call.sessionId}',
      );
      return;
    }

    _automaticUploadRetryAttempts[filePath] = attempt + 1;
    _cancelAutomaticUploadRetryTimer(filePath);
    debugPrint(
      'RECORDING_UPLOAD: retry scheduled in '
      '${delay.inSeconds}s attempt=${attempt + 1} session=${call.sessionId}',
    );
    _automaticUploadRetryTimers[filePath] = Timer(delay, () {
      _automaticUploadRetryTimers.remove(filePath);
      unawaited(
        _retryMatchedRecording(
          customer: customer,
          recording: recording,
          call: call,
        ),
      );
    });
  }

  Future<void> _retryMatchedRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
    required CallModel call,
  }) async {
    if (_activeErpNextSession == null ||
        recordingUploadState(recording) == RecordingUploadState.uploaded) {
      return;
    }

    final customerId = customer.erpNextCustomerId;
    final currentCustomer =
        (customerId == null ? null : _customerForErpNextId(customerId)) ??
        _customerForPhone(customer.phoneNumber) ??
        customer;

    debugPrint('RECORDING_UPLOAD: automatic retry session=${call.sessionId}');
    _updateCustomer(
      currentCustomer.phoneNumber,
      (current) =>
          current.copyWith(statusLabel: 'Retrying recording upload...'),
    );
    final uploaded = await _uploadMatchedRecording(
      customer: currentCustomer,
      recording: recording,
      call: call,
    );
    _updateCustomer(
      currentCustomer.phoneNumber,
      (current) => current.copyWith(
        statusLabel: uploaded
            ? 'Recording uploaded'
            : 'Recording saved; automatic retry pending',
      ),
    );
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    if (_isDisposed) return;
    final isConnected = results.any(
      (result) => result != ConnectivityResult.none,
    );
    final connectivityWasLost = _wasDisconnected == true;
    _wasDisconnected = !isConnected;

    if (!isConnected) {
      for (final timer in _automaticUploadRetryTimers.values) {
        timer.cancel();
      }
      _automaticUploadRetryTimers.clear();
      if (_pendingRecordingUploads.isNotEmpty) {
        debugPrint(
          'RECORDING_UPLOAD: connectivity lost; paused '
          '${_pendingRecordingUploads.length} pending upload(s)',
        );
      }
      return;
    }

    if (!connectivityWasLost || _activeErpNextSession == null) {
      return;
    }

    unawaited(refreshDraftPaymentCustomers());
    unawaited(_processPersistedWork());

    final pendingUploads = List<_PendingRecordingUpload>.from(
      _pendingRecordingUploads.values,
    );
    if (pendingUploads.isEmpty) return;

    debugPrint(
      'RECORDING_UPLOAD: connectivity restored; retrying '
      '${pendingUploads.length} pending recording(s)',
    );
    for (final pending in pendingUploads) {
      _cancelAutomaticUploadRetryTimer(pending.recording.filePath);
      unawaited(
        _retryMatchedRecording(
          customer: pending.customer,
          recording: pending.recording,
          call: pending.call,
        ),
      );
    }
  }

  void _cancelAutomaticUploadRetryTimer(String filePath) {
    _automaticUploadRetryTimers.remove(filePath)?.cancel();
  }

  void _clearAutomaticUploadRetry(String filePath) {
    _cancelAutomaticUploadRetryTimer(filePath);
    _automaticUploadRetryAttempts.remove(filePath);
    _pendingRecordingUploads.remove(filePath);
  }

  void _cancelAllAutomaticUploadRetries() {
    for (final timer in _automaticUploadRetryTimers.values) {
      timer.cancel();
    }
    _automaticUploadRetryTimers.clear();
    _automaticUploadRetryAttempts.clear();
    _pendingRecordingUploads.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelAllAutomaticUploadRetries();
    _draftCustomerRefreshTimer?.cancel();
    _persistedWorkTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _markPaymentEntriesCompleted(CustomerContact customer) async {
    if (customer.paymentEntryIds.isEmpty) return;

    _completedPaymentEntryIds.addAll(customer.paymentEntryIds);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sortedIds = _completedPaymentEntryIds.toList()..sort();
      await prefs.setStringList(_completedPaymentEntriesKey, sortedIds);
    } catch (error) {
      debugPrint(
        'RECORDING_UPLOAD: could not persist completed payment entries: $error',
      );
    }
  }

  CallModel? _callForRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
  }) {
    final draftCreatedAt = customer.latestPaymentEntryCreatedAt;
    final recordedCallStartedAt = _callStartForCurrentDraft(customer);
    final inferredStartedAt =
        recordedCallStartedAt ?? recording.effectiveTimestamp;
    PersistedCallSession? ledgerSession;
    for (final session in _callSessions.reversed) {
      if (_normalize(session.phoneNumber) == _normalize(customer.phoneNumber) &&
          session.startedAt.difference(inferredStartedAt).abs() <=
              _recordingWindowDuration) {
        ledgerSession = session;
        break;
      }
    }
    final startedAt = ledgerSession?.startedAt ?? inferredStartedAt;
    if (draftCreatedAt != null && startedAt.isBefore(draftCreatedAt)) {
      return null;
    }

    final endedAt = recordedCallStartedAt == null
        ? recording.lastModifiedTime
        : customer.lastCallEndedAt ?? recording.lastModifiedTime;
    final durationSeconds = endedAt.isAfter(startedAt)
        ? endedAt.difference(startedAt).inSeconds
        : 0;
    final normalizedPhone =
        _normalize(customer.phoneNumber) ?? customer.phoneNumber;
    final phoneId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final sessionId =
        ledgerSession?.id ??
        'call_${phoneId}_${startedAt.millisecondsSinceEpoch}_${recording.lastModifiedTime.millisecondsSinceEpoch}';

    return CallModel(
      sessionId: sessionId,
      phoneNumber: customer.phoneNumber,
      callType: 'outgoing',
      duration: durationSeconds,
      audioPath: recording.filePath,
      status: 'pending',
      createdAt: startedAt.toIso8601String(),
    );
  }

  CallModel _callForPersistedRecording({
    required PersistedCallSession session,
    required CallRecordingFile recording,
  }) {
    final endedAt = session.endedAt ?? recording.lastModifiedTime;
    final durationSeconds = endedAt.isAfter(session.startedAt)
        ? endedAt.difference(session.startedAt).inSeconds
        : 0;
    return CallModel(
      sessionId: session.id,
      phoneNumber: session.phoneNumber,
      callType: 'outgoing',
      duration: durationSeconds,
      audioPath: recording.filePath,
      status: 'pending',
      createdAt: session.startedAt.toIso8601String(),
    );
  }

  List<_MatchedRecordingTarget> get _matchedRecordingTargets {
    final targets = <_MatchedRecordingTarget>[];
    final seenPaths = <String>{};

    for (final customer in _customers) {
      final recording =
          customer.latestRecording ??
          (customer.availableRecordings.isEmpty
              ? null
              : customer.availableRecordings.first);
      if (recording != null && seenPaths.add(recording.filePath)) {
        targets.add(
          _MatchedRecordingTarget(customer: customer, recording: recording),
        );
      }
    }

    return targets;
  }

  String _startedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_started_at';

  String _endedAtKey(String normalizedPhone) =>
      'customer_${normalizedPhone}_last_call_ended_at';

  void _handlePlaybackEnded(String filePath) {
    if (_activeRecordingPath != filePath) return;
    _activeRecordingPath = null;
    _isRecordingPlaying = false;
    _notifyListeners();
  }
}

class _MatchedRecordingTarget {
  final CustomerContact customer;
  final CallRecordingFile recording;

  const _MatchedRecordingTarget({
    required this.customer,
    required this.recording,
  });
}
