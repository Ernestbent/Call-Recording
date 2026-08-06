import 'package:calls_recording/db/call_model.dart';
import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/repository/call_repository.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'matched recording uploads automatically when a call completes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final persistence = _FakeCallPersistence();
      final uploader = _FakeRecordingUploader();
      final store = CustomerCallStore(
        callPersistence: persistence,
        recordingUploader: uploader,
        initialCustomers: const [
          CustomerContact(
            erpNextCustomerId: 'CUST-TEST-001',
            name: 'Test Customer',
            phoneNumber: '0772835195',
            subtitle: '1 draft payment entry',
            statusLabel: 'Ready to call',
          ),
        ],
      );
      final startedAt = DateTime(2026, 8, 3, 12);
      final endedAt = startedAt.add(const Duration(seconds: 45));
      final recording = CallRecordingFile(
        filePath: '/recordings/test-call.mp3',
        fileName: 'test-call.mp3',
        lastModifiedTime: endedAt,
      );

      store.markCallStarted('0772835195', startedAt: startedAt);
      await store.markCallCompleted(
        phoneNumber: '0772835195',
        callEndedAt: endedAt,
        recording: recording,
      );

      expect(uploader.uploadedCalls, hasLength(1));
      expect(uploader.customerIds, ['CUST-TEST-001']);
      expect(persistence.savedCalls.single['status'], 'uploaded');
      expect(
        store.recordingUploadState(recording),
        RecordingUploadState.uploaded,
      );
      expect(store.customers.single.statusLabel, 'Recording uploaded');
      expect(store.customersToCall, isEmpty);
    },
  );
}

class _FakeRecordingUploader implements RecordingUploader {
  final List<CallModel> uploadedCalls = [];
  final List<String?> customerIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<RecordingUploadResult> upload({
    required CallModel call,
    String? customerId,
  }) async {
    uploadedCalls.add(call);
    customerIds.add(customerId);
    return const RecordingUploadResult(
      uploadId: '1',
      message: 'Recording uploaded successfully.',
    );
  }
}

class _FakeCallPersistence implements CallPersistence {
  final List<Map<String, dynamic>> savedCalls = [];

  @override
  Future<Map<String, dynamic>?> getCall(String sessionId) async {
    for (final call in savedCalls.reversed) {
      if (call['session_id'] == sessionId) return call;
    }
    return null;
  }

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {
    savedCalls.add(Map<String, dynamic>.from(call));
  }

  @override
  Future<void> updateStatus(String sessionId, String status) async {
    final call = await getCall(sessionId);
    call?['status'] = status;
  }
}
