import 'package:calls_recording/models/call_recording_file.dart';

enum PersistedCallStatus {
  waitingForRecording,
  recordingNotFound,
  pendingUpload,
  uploaded,
}

class PersistedCallSession {
  final String id;
  final String? customerId;
  final String customerName;
  final String phoneNumber;
  final List<String> paymentEntryIds;
  final DateTime? draftCreatedAt;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? recordingPath;
  final String? recordingName;
  final DateTime? recordingModifiedAt;
  final PersistedCallStatus status;
  final DateTime statusChangedAt;
  final String? lastError;

  const PersistedCallSession({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phoneNumber,
    required this.paymentEntryIds,
    required this.draftCreatedAt,
    required this.startedAt,
    required this.endedAt,
    required this.recordingPath,
    required this.recordingName,
    required this.recordingModifiedAt,
    required this.status,
    DateTime? statusChangedAt,
    required this.lastError,
  }) : statusChangedAt = statusChangedAt ?? endedAt ?? startedAt;

  CallRecordingFile? get recording {
    final path = recordingPath;
    final name = recordingName;
    final modifiedAt = recordingModifiedAt;
    if (path == null || name == null || modifiedAt == null) return null;
    return CallRecordingFile(
      filePath: path,
      fileName: name,
      lastModifiedTime: modifiedAt,
    );
  }

  PersistedCallSession copyWith({
    String? customerId,
    String? customerName,
    List<String>? paymentEntryIds,
    DateTime? draftCreatedAt,
    DateTime? endedAt,
    CallRecordingFile? recording,
    PersistedCallStatus? status,
    DateTime? statusChangedAt,
    String? lastError,
    bool clearError = false,
  }) {
    final nextStatus = status ?? this.status;
    return PersistedCallSession(
      id: id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      phoneNumber: phoneNumber,
      paymentEntryIds: paymentEntryIds ?? this.paymentEntryIds,
      draftCreatedAt: draftCreatedAt ?? this.draftCreatedAt,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      recordingPath: recording?.filePath ?? recordingPath,
      recordingName: recording?.fileName ?? recordingName,
      recordingModifiedAt: recording?.lastModifiedTime ?? recordingModifiedAt,
      status: nextStatus,
      statusChangedAt:
          statusChangedAt ??
          (nextStatus == this.status ? this.statusChangedAt : DateTime.now()),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'customer_name': customerName,
    'phone_number': phoneNumber,
    'payment_entry_ids': paymentEntryIds,
    'draft_created_at': draftCreatedAt?.toIso8601String(),
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'recording_path': recordingPath,
    'recording_name': recordingName,
    'recording_modified_at': recordingModifiedAt?.toIso8601String(),
    'status': status.name,
    'status_changed_at': statusChangedAt.toIso8601String(),
    'last_error': lastError,
  };

  factory PersistedCallSession.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    final startedAt =
        DateTime.tryParse(json['started_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final endedAt = DateTime.tryParse(json['ended_at']?.toString() ?? '');
    return PersistedCallSession(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString() ?? 'Unknown customer',
      phoneNumber: json['phone_number']?.toString() ?? '',
      paymentEntryIds:
          (json['payment_entry_ids'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const [],
      draftCreatedAt: DateTime.tryParse(
        json['draft_created_at']?.toString() ?? '',
      ),
      startedAt: startedAt,
      endedAt: endedAt,
      recordingPath: json['recording_path']?.toString(),
      recordingName: json['recording_name']?.toString(),
      recordingModifiedAt: DateTime.tryParse(
        json['recording_modified_at']?.toString() ?? '',
      ),
      status: PersistedCallStatus.values.firstWhere(
        (status) => status.name == statusName,
        orElse: () => PersistedCallStatus.waitingForRecording,
      ),
      statusChangedAt:
          DateTime.tryParse(json['status_changed_at']?.toString() ?? '') ??
          endedAt ??
          startedAt,
      lastError: json['last_error']?.toString(),
    );
  }
}
