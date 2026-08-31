import 'dart:async';

import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/erpnext_session.dart';
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

  CustomerCallStore({
    CallPersistence? callPersistence,
    DraftPaymentCustomerSource? customerSource,
    RecordingUploader? recordingUploader,
    List<Duration> automaticUploadRetryDelays =
        _defaultAutomaticUploadRetryDelays,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    List<CustomerContact> initialCustomers = const [],
  }) : _callPersistence = callPersistence ?? CallRepository(),
       _customerSource = customerSource ?? ErpNextCustomerService(),
       _recordingUploader = recordingUploader ?? HttpRecordingUploader(),
       _automaticUploadRetryDelays = List.unmodifiable(
         automaticUploadRetryDelays,
       ),
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
  final CallPersistence _callPersistence;
  final DraftPaymentCustomerSource _customerSource;
  final RecordingUploader _recordingUploader;
  final List<Duration> _automaticUploadRetryDelays;
  final Map<String, RecordingUploadState> _recordingUploadStates = {};
  final Map<String, Timer> _automaticUploadRetryTimers = {};
  final Map<String, int> _automaticUploadRetryAttempts = {};
  final Map<String, _PendingRecordingUpload> _pendingRecordingUploads = {};
  final Set<String> _completedPaymentEntryIds = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool? _wasDisconnected;
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

    for (var i = 0; i < _customers.length; i++) {
      _customers[i] = _withPersistedCallTimestamps(_customers[i], prefs);
    }

    _notifyListeners();
  }

  List<CustomerContact> get customers => List.unmodifiable(_customers);
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

  int get matchedRecordingsCount => _matchedRecordingTargets.length;

  int get pendingRecordingUploadsCount => _matchedRecordingTargets
      .where(
        (target) =>
            recordingUploadState(target.recording) !=
            RecordingUploadState.uploaded,
      )
      .length;

  void clearErpNextSession() {
    _cancelAllAutomaticUploadRetries();
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
        notifyListeners();
      }
    }
  }

  Future<RecordingBatchUploadResult> uploadAllRecordings() async {
    final targets = _matchedRecordingTargets;
    if (_isUploadingAllRecordings) {
      return RecordingBatchUploadResult(
        total: targets.length,
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
        total: targets.length,
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
      _completedPaymentEntryIds
        ..clear()
        ..addAll(prefs.getStringList(_completedPaymentEntriesKey) ?? const []);
      if (loadGeneration != _customerLoadGeneration) {
        return _customers.length;
      }

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
        final draftLabel = visibleDraftPaymentCount == 1
            ? '1 draft payment entry'
            : '$visibleDraftPaymentCount draft payment entries';
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
          draftPaymentCount: visibleDraftPaymentCount,
          paymentEntryIds: remoteCustomer.paymentEntryIds,
          latestPaymentEntryCreatedAt:
              remoteCustomer.latestPaymentEntryCreatedAt,
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
      await reconcileCompletedBackgroundCalls();
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
    if (_customers.isEmpty) return;

    final completedCalls = await ServiceStarter.consumeCompletedCalls();
    for (final completedCall in completedCalls) {
      final phoneNumber = completedCall.phoneNumber;
      if (phoneNumber == null || phoneNumber.trim().isEmpty) continue;

      markCallStarted(phoneNumber, startedAt: completedCall.startedAt);
      await markCallCompleted(
        phoneNumber: phoneNumber,
        callEndedAt: completedCall.endedAt,
        recording: completedCall.recording,
      );
    }
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

        _updateCustomer(
          customer.phoneNumber,
          (current) => current.copyWith(
            statusLabel: latestRecording == null
                ? current.lastCallStartedAt == null
                      ? 'Ready to call'
                      : 'No recordings matched the last app call'
                : uploadFailed
                ? 'Recording saved; upload pending'
                : 'Recording uploaded',
            latestRecording: latestRecording,
            availableRecordings: latestRecording == null
                ? const []
                : [latestRecording],
            matchingRecordingsCount: latestRecording == null ? 0 : 1,
            clearRecording: latestRecording == null,
            isCallQueued: false,
            isCallInProgress: false,
          ),
        );
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
              '${customer.erpNextCustomerId}:${_normalize(customer.phoneNumber)}',
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

    return matches.take(1).toList(growable: false);
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

  Future<CallModel?> _saveMatchedRecording({
    required CustomerContact customer,
    required CallRecordingFile recording,
  }) async {
    final call = _callForRecording(customer: customer, recording: recording);
    if (call == null) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError =
          'The call start time is missing. This recording remains pending.';
      _notifyListeners();
      return null;
    }

    final existingCall = await _callPersistence.getCall(call.sessionId);
    if (existingCall?['status'] == 'uploaded') {
      await _markPaymentEntriesCompleted(customer);
      _recordingUploadStates[recording.filePath] =
          RecordingUploadState.uploaded;
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
      _lastRecordingUploadError = null;
      debugPrint('RECORDING_UPLOAD: uploaded session=${call.sessionId}');
      _notifyListeners();
      return true;
    } on RecordingUploadException catch (error) {
      _recordingUploadStates[recording.filePath] = RecordingUploadState.failed;
      _lastRecordingUploadError = error.message;
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
        _customerForPhone(customer.phoneNumber);
    if (currentCustomer == null) {
      _clearAutomaticUploadRetry(recording.filePath);
      return;
    }

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
    _cancelAllAutomaticUploadRetries();
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
    final startedAt = customer.lastCallStartedAt;
    if (startedAt == null) return null;

    final endedAt = customer.lastCallEndedAt ?? recording.lastModifiedTime;
    final durationSeconds = endedAt.isAfter(startedAt)
        ? endedAt.difference(startedAt).inSeconds
        : 0;
    final normalizedPhone =
        _normalize(customer.phoneNumber) ?? customer.phoneNumber;
    final phoneId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final sessionId =
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
