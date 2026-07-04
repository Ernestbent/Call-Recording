import 'package:calls_recording/models/call_recording_file.dart';

class CustomerContact {
  final String name;
  final String phoneNumber;
  final String subtitle;
  final String statusLabel;
  final DateTime? lastCallStartedAt;
  final DateTime? lastCallEndedAt;
  final CallRecordingFile? latestRecording;
  final int matchingRecordingsCount;
  final bool isCallQueued;
  final bool isCallInProgress;

  const CustomerContact({
    required this.name,
    required this.phoneNumber,
    required this.subtitle,
    required this.statusLabel,
    this.lastCallStartedAt,
    this.lastCallEndedAt,
    this.latestRecording,
    this.matchingRecordingsCount = 0,
    this.isCallQueued = false,
    this.isCallInProgress = false,
  });

  CustomerContact copyWith({
    String? name,
    String? phoneNumber,
    String? subtitle,
    String? statusLabel,
    DateTime? lastCallStartedAt,
    DateTime? lastCallEndedAt,
    CallRecordingFile? latestRecording,
    int? matchingRecordingsCount,
    bool clearRecording = false,
    bool? isCallQueued,
    bool? isCallInProgress,
  }) {
    return CustomerContact(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      subtitle: subtitle ?? this.subtitle,
      statusLabel: statusLabel ?? this.statusLabel,
      lastCallStartedAt: lastCallStartedAt ?? this.lastCallStartedAt,
      lastCallEndedAt: lastCallEndedAt ?? this.lastCallEndedAt,
      latestRecording: clearRecording
          ? null
          : (latestRecording ?? this.latestRecording),
      matchingRecordingsCount:
          matchingRecordingsCount ?? this.matchingRecordingsCount,
      isCallQueued: isCallQueued ?? this.isCallQueued,
      isCallInProgress: isCallInProgress ?? this.isCallInProgress,
    );
  }
}
