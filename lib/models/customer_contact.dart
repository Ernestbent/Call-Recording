import 'package:calls_recording/models/call_recording_file.dart';

class CustomerContact {
  final String? erpNextCustomerId;
  final String name;
  final String phoneNumber;
  final String? profileImageUrl;
  final Map<String, String> profileImageHeaders;
  final int draftPaymentCount;
  final String subtitle;
  final String statusLabel;
  final DateTime? lastCallStartedAt;
  final DateTime? lastCallEndedAt;
  final CallRecordingFile? latestRecording;
  final List<CallRecordingFile> availableRecordings;
  final int matchingRecordingsCount;
  final bool isCallQueued;
  final bool isCallInProgress;

  const CustomerContact({
    this.erpNextCustomerId,
    required this.name,
    required this.phoneNumber,
    this.profileImageUrl,
    this.profileImageHeaders = const {},
    this.draftPaymentCount = 0,
    required this.subtitle,
    required this.statusLabel,
    this.lastCallStartedAt,
    this.lastCallEndedAt,
    this.latestRecording,
    this.availableRecordings = const [],
    this.matchingRecordingsCount = 0,
    this.isCallQueued = false,
    this.isCallInProgress = false,
  });

  CustomerContact copyWith({
    String? erpNextCustomerId,
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
    Map<String, String>? profileImageHeaders,
    int? draftPaymentCount,
    String? subtitle,
    String? statusLabel,
    DateTime? lastCallStartedAt,
    DateTime? lastCallEndedAt,
    CallRecordingFile? latestRecording,
    List<CallRecordingFile>? availableRecordings,
    int? matchingRecordingsCount,
    bool clearRecording = false,
    bool? isCallQueued,
    bool? isCallInProgress,
  }) {
    return CustomerContact(
      erpNextCustomerId: erpNextCustomerId ?? this.erpNextCustomerId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      profileImageHeaders: profileImageHeaders ?? this.profileImageHeaders,
      draftPaymentCount: draftPaymentCount ?? this.draftPaymentCount,
      subtitle: subtitle ?? this.subtitle,
      statusLabel: statusLabel ?? this.statusLabel,
      lastCallStartedAt: lastCallStartedAt ?? this.lastCallStartedAt,
      lastCallEndedAt: lastCallEndedAt ?? this.lastCallEndedAt,
      latestRecording: clearRecording
          ? null
          : (latestRecording ?? this.latestRecording),
      availableRecordings: clearRecording
          ? const []
          : (availableRecordings ?? this.availableRecordings),
      matchingRecordingsCount:
          matchingRecordingsCount ?? this.matchingRecordingsCount,
      isCallQueued: isCallQueued ?? this.isCallQueued,
      isCallInProgress: isCallInProgress ?? this.isCallInProgress,
    );
  }
}
