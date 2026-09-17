import 'dart:convert';

import 'package:calls_recording/models/persisted_call_session.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/screens/session.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Sessions defaults to active work and safely clears history', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 16, 15);
    final sessions = [
      _session('waiting', PersistedCallStatus.waitingForRecording, now),
      _session('pending', PersistedCallStatus.pendingUpload, now),
      _session('uploaded', PersistedCallStatus.uploaded, now),
      _session('missing', PersistedCallStatus.recordingNotFound, now),
    ];
    SharedPreferences.setMockInitialValues({
      'persistent_call_session_ledger': jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      ),
    });
    final store = CustomerCallStore(
      callPersistence: _MemoryCallPersistence(),
      automaticDraftCustomerRefreshEnabled: false,
      now: () => now,
    );
    addTearDown(store.dispose);
    await store.hydrate();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SessionsScreen(appState: store),
      ),
    );

    expect(find.text('Active (2)'), findsOneWidget);
    expect(find.text('History (2)'), findsOneWidget);
    expect(find.text('waiting'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
    expect(find.text('uploaded'), findsNothing);

    await tester.tap(find.text('History (2)'));
    await tester.pumpAndSettle();
    expect(find.text('uploaded'), findsOneWidget);
    expect(find.text('missing'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-session-history-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-session-history')));
    await tester.pumpAndSettle();

    expect(find.text('History (0)'), findsOneWidget);
    expect(store.activeCallSessions, hasLength(2));
    expect(store.sessionHistory, isEmpty);
  });
}

PersistedCallSession _session(
  String id,
  PersistedCallStatus status,
  DateTime now,
) {
  final hasRecording =
      status == PersistedCallStatus.pendingUpload ||
      status == PersistedCallStatus.uploaded;
  return PersistedCallSession(
    id: id,
    customerId: 'CUST-$id',
    customerName: id,
    phoneNumber: '0700000000',
    paymentEntryIds: const [],
    draftCreatedAt: now.subtract(const Duration(hours: 1)),
    startedAt: now.subtract(const Duration(minutes: 2)),
    endedAt: now.subtract(const Duration(minutes: 1)),
    recordingPath: hasRecording ? '/recordings/$id.aac' : null,
    recordingName: hasRecording ? '$id.aac' : null,
    recordingModifiedAt: hasRecording ? now : null,
    status: status,
    statusChangedAt: now,
    lastError: null,
  );
}

class _MemoryCallPersistence implements CallPersistence {
  @override
  Future<void> deleteCalls(
    Iterable<String> sessionIds, {
    Iterable<String> audioPaths = const [],
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> getAllCalls() async => const [];

  @override
  Future<Map<String, dynamic>?> getCall(String sessionId) async => null;

  @override
  Future<Map<String, dynamic>?> getCallByAudioPath(String audioPath) async =>
      null;

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {}

  @override
  Future<void> updateStatus(String sessionId, String status) async {}
}
