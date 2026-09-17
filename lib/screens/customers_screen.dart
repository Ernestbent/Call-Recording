import 'dart:math' as math;

import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:flutter/material.dart';

class CustomersScreen extends StatelessWidget {
  final CustomerCallStore appState;

  const CustomersScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          AnimatedBuilder(
            animation: appState,
            builder: (context, _) {
              return IconButton(
                tooltip: 'Refresh ERPNext customers',
                onPressed: appState.isLoadingCustomers
                    ? null
                    : () async {
                        final count = await appState
                            .refreshDraftPaymentCustomers();
                        if (!context.mounted) return;

                        final error = appState.customerLoadError;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error ??
                                  'Loaded $count draft-payment customer${count == 1 ? '' : 's'}.',
                            ),
                          ),
                        );
                      },
                icon: appState.isLoadingCustomers
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final customers = appState.customersToCall;
            final hasCompletedCalls =
                appState.customers.length > customers.length;

            Widget buildCustomerCard(CustomerContact customer) {
              return _CustomerCard(
                customer: customer,
                onCallTap: () async {
                  final didOpen = await appState.dialCustomer(customer);

                  if (!context.mounted || didOpen) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to open dialer right now.'),
                    ),
                  );
                },
                onPlayTap: (recording) async {
                  final wasPlaying = appState.isPlayingRecording(recording);
                  final didStart = await appState.playRecording(recording);
                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        didStart
                            ? wasPlaying
                                  ? 'Playback paused'
                                  : 'Playing ${recording.fileName}'
                            : 'Unable to play this recording.',
                      ),
                    ),
                  );
                },
                isActiveRecording: appState.isActiveRecording,
                isPlayingRecording: appState.isPlayingRecording,
              );
            }

            Widget buildHeader() {
              return Column(
                key: const Key('customers-fixed-header'),
                children: [
                  if (appState.isLoadingCustomers) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 14),
                  ],
                  if (appState.customerLoadError != null) ...[
                    _CustomerLoadError(message: appState.customerLoadError!),
                    const SizedBox(height: 14),
                  ],
                  _SummaryCard(customersToCallCount: customers.length),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('fetch-all-recordings-button'),
                      onPressed:
                          appState.isFetchingAllRecordings ||
                              appState.isUploadingAllRecordings
                          ? null
                          : () async {
                              final matches = await appState
                                  .fetchRecordingsForAllCustomers();

                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    matches == 0
                                        ? 'No recordings matched calls made from this app.'
                                        : 'Matched recordings for $matches customer${matches == 1 ? '' : 's'}.',
                                  ),
                                ),
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: Icon(
                        appState.isFetchingAllRecordings
                            ? Icons.sync_rounded
                            : Icons.library_music_rounded,
                        size: 18,
                      ),
                      label: Text(
                        appState.isFetchingAllRecordings
                            ? 'Scanning recordings...'
                            : 'Rescan Recordings',
                        style: const TextStyle(
                          fontFamily: 'Bubblegum Sans',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  if (appState.canImportTestRecording) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('import-test-recording-button'),
                        onPressed:
                            appState.isFetchingAllRecordings ||
                                appState.isUploadingAllRecordings
                            ? null
                            : () async {
                                final imported = await appState
                                    .importLatestSavedRecordingForTest();
                                if (!context.mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      imported
                                          ? appState.lastRecordingUploadError ==
                                                    null
                                                ? 'Loaded and uploaded one saved recording for ${appState.testRecordingPhoneNumber}.'
                                                : 'Loaded one saved recording for ${appState.testRecordingPhoneNumber}. Automatic upload will retry.'
                                          : appState.lastRecordingUploadError ??
                                                'No matching test recording was found.',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.science_rounded, size: 18),
                        label: Text(
                          'Load Test Recording (${appState.testRecordingPhoneNumber})',
                          style: const TextStyle(
                            fontFamily: 'Bubblegum Sans',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('upload-all-recordings-button'),
                      onPressed:
                          appState.isUploadingAllRecordings ||
                              appState.isFetchingAllRecordings ||
                              appState.matchedRecordingsCount == 0 ||
                              appState.pendingRecordingUploadsCount == 0
                          ? null
                          : () async {
                              final result = await appState
                                  .uploadAllRecordings();
                              if (!context.mounted) return;

                              final message = switch (result) {
                                RecordingBatchUploadResult(total: 0) =>
                                  'Fetch or record calls before uploading.',
                                RecordingBatchUploadResult(
                                  attempted: 0,
                                  failed: 0,
                                ) =>
                                  'All recordings are already uploaded.',
                                RecordingBatchUploadResult(failed: 0) =>
                                  'Uploaded ${result.uploaded} recording${result.uploaded == 1 ? '' : 's'}.',
                                _ =>
                                  'Uploaded ${result.uploaded} of ${result.attempted}. ${result.failed} recording${result.failed == 1 ? '' : 's'} remain pending. ${appState.lastRecordingUploadError ?? ''}',
                              };

                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: appState.isUploadingAllRecordings
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(
                        appState.isUploadingAllRecordings
                            ? 'Uploading all recordings...'
                            : appState.pendingRecordingUploadsCount == 0 &&
                                  appState.matchedRecordingsCount > 0
                            ? 'No Pending Uploads'
                            : 'Retry Pending Uploads (${appState.pendingRecordingUploadsCount})',
                        style: const TextStyle(
                          fontFamily: 'Bubblegum Sans',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SectionLabel(
                    'Customer calls',
                    trailing: Text(
                      '${customers.length} contacts',
                      style: const TextStyle(
                        color: AppColors.subtle,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }

            List<Widget> buildCustomerSlivers() {
              return [
                if (customers.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyCustomersState(
                      hasCompletedCalls: hasCompletedCalls,
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index.isOdd) {
                        return const SizedBox(height: 12);
                      }
                      return buildCustomerCard(customers[index ~/ 2]);
                    }, childCount: (customers.length * 2) - 1),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ];
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxHeight < 360) {
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: buildHeader()),
                        ...buildCustomerSlivers(),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      buildHeader(),
                      Expanded(
                        child: CustomScrollView(
                          key: const Key('customer-cards-scroll-view'),
                          slivers: buildCustomerSlivers(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 1,
        appState: appState,
        onTap: (_) {},
      ),
    );
  }
}

class _EmptyCustomersState extends StatelessWidget {
  final bool hasCompletedCalls;

  const _EmptyCustomersState({required this.hasCompletedCalls});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppSurfaces.placeholder(radius: 16),
      child: Row(
        children: [
          const Icon(
            Icons.people_outline_rounded,
            color: AppColors.subtle,
            size: 22,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              hasCompletedCalls
                  ? 'No customers are waiting for a call. Uploaded calls remain available in Recent Activity.'
                  : 'No customers with draft Payment Entries and a mobile number were found.',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerLoadError extends StatelessWidget {
  final String message;

  const _CustomerLoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int customersToCallCount;

  const _SummaryCard({required this.customersToCallCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('customers-summary-card'),
      width: double.infinity,
      height: 156,
      decoration: AppSurfaces.card(radius: 18),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'CUSTOMERS TO CALL',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$customersToCallCount',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 42,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Draft-payment customers waiting',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: Image.asset(
              'lib/images/headphone.png',
              width: 54,
              height: 54,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'Headphones',
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final CustomerContact customer;
  final VoidCallback onCallTap;
  final ValueChanged<CallRecordingFile> onPlayTap;
  final bool Function(CallRecordingFile) isActiveRecording;
  final bool Function(CallRecordingFile) isPlayingRecording;

  const _CustomerCard({
    required this.customer,
    required this.onCallTap,
    required this.onPlayTap,
    required this.isActiveRecording,
    required this.isPlayingRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: AppSurfaces.card(radius: 16, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CustomerAvatar(
                key: Key('customer-avatar-${customer.phoneNumber}'),
                name: customer.name,
                imageUrl: customer.profileImageUrl,
                imageHeaders: customer.profileImageHeaders,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontFamily: 'Bubblegum Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.phoneNumber,
                      style: const TextStyle(
                        fontFamily: 'Bubblegum Sans',
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.subtitle,
                      style: const TextStyle(
                        fontFamily: 'Bubblegum Sans',
                        fontSize: 12,
                        color: AppColors.subtle,
                      ),
                    ),
                  ],
                ),
              ),
              _CallButton(
                key: Key('call-customer-${customer.phoneNumber}'),
                onPressed: onCallTap,
                customerName: customer.name,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customer.latestPaymentEntryCreatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              _formatPaymentEntryCreatedAt(
                customer.latestPaymentEntryCreatedAt!,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Bubblegum Sans',
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
          ],
          if (customer.statusLabel != 'Ready to call' &&
              !customer.statusLabel.toLowerCase().contains('upload pending') &&
              !customer.statusLabel.toLowerCase().contains('recording ready') &&
              !customer.statusLabel.toLowerCase().contains(
                'recordings ready',
              )) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(
                    customer.isCallInProgress
                        ? Icons.phone_in_talk_rounded
                        : Icons.fiber_manual_record_rounded,
                    size: 16,
                    color: customer.isCallInProgress
                        ? AppColors.primary
                        : AppColors.subtle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customer.statusLabel,
                      style: const TextStyle(
                        fontFamily: 'Bubblegum Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _RecordingPanel(
            recordings: customer.availableRecordings.isEmpty
                ? [
                    if (customer.latestRecording != null)
                      customer.latestRecording!,
                  ]
                : customer.availableRecordings,
            lastCallStartedAt: customer.lastCallStartedAt,
            lastCallEndedAt: customer.lastCallEndedAt,
            onPlayTap: onPlayTap,
            isActiveRecording: isActiveRecording,
            isPlayingRecording: isPlayingRecording,
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  static String _formatPaymentEntryCreatedAt(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Payment entry created ${local.day} ${months[local.month - 1]} ${local.year} at $hour:$minute';
  }
}

class _CallButton extends StatelessWidget {
  final String customerName;
  final VoidCallback onPressed;

  const _CallButton({
    super.key,
    required this.customerName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Call $customerName',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Call',
          style: TextStyle(
            fontFamily: 'Bubblegum Sans',
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CustomerAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final Map<String, String> imageHeaders;

  const _CustomerAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.imageHeaders,
  });

  void _showLargeImage(BuildContext context, String resolvedImageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        return Dialog.fullscreen(
          key: const Key('customer-image-viewer'),
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        resolvedImageUrl,
                        headers: imageHeaders,
                        width: screenSize.width,
                        height: screenSize.height,
                        fit: BoxFit.contain,
                        semanticLabel: 'Large photo of $name',
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (_, _, _) => const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 52,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Unable to load this customer photo.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    key: const Key('close-customer-image-viewer'),
                    tooltip: 'Close photo',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 72,
                  bottom: 18,
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = imageUrl?.trim();
    final hasImage = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;
    final fallback = Center(
      child: Text(
        _CustomerCard._initials(name),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: AppColors.primarySoft,
        child: SizedBox(
          width: 48,
          height: 48,
          child: !hasImage
              ? fallback
              : Image.network(
                  resolvedImageUrl,
                  headers: imageHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );

    if (!hasImage) return avatar;

    return Semantics(
      button: true,
      label: 'View photo of $name',
      child: Tooltip(
        message: 'View photo of $name',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showLargeImage(context, resolvedImageUrl),
            borderRadius: BorderRadius.circular(14),
            child: avatar,
          ),
        ),
      ),
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  final List<CallRecordingFile> recordings;
  final DateTime? lastCallStartedAt;
  final DateTime? lastCallEndedAt;
  final ValueChanged<CallRecordingFile> onPlayTap;
  final bool Function(CallRecordingFile) isActiveRecording;
  final bool Function(CallRecordingFile) isPlayingRecording;

  const _RecordingPanel({
    required this.recordings,
    required this.lastCallStartedAt,
    required this.lastCallEndedAt,
    required this.onPlayTap,
    required this.isActiveRecording,
    required this.isPlayingRecording,
  });

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (var index = 0; index < recordings.length; index++) ...[
          _RecordingRow(
            recording: recordings[index],
            lastCallStartedAt: lastCallStartedAt,
            onPlayTap: () => onPlayTap(recordings[index]),
            isActive: isActiveRecording(recordings[index]),
            isPlaying: isPlayingRecording(recordings[index]),
          ),
          if (index != recordings.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  static String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month ${value.year} • $hour:$minute';
  }
}

class _RecordingRow extends StatelessWidget {
  final CallRecordingFile recording;
  final DateTime? lastCallStartedAt;
  final VoidCallback onPlayTap;
  final bool isActive;
  final bool isPlaying;

  const _RecordingRow({
    required this.recording,
    required this.lastCallStartedAt,
    required this.onPlayTap,
    required this.isActive,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppSurfaces.card(
        color: isActive ? AppColors.primarySoft : AppColors.surfaceMuted,
        radius: 12,
        elevated: false,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '${isPlaying ? 'Pause' : 'Play'} ${recording.fileName}',
            child: InkWell(
              key: ValueKey('play-recording-${recording.filePath}'),
              onTap: onPlayTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _AudioWaveform(isActive: isActive, isPlaying: isPlaying),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lastCallStartedAt != null)
                  Text(
                    'Call time ${_formatDateTime(lastCallStartedAt!)}',
                    style: const TextStyle(
                      fontFamily: 'Bubblegum Sans',
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                if (lastCallStartedAt != null) const SizedBox(height: 4),
                Text(
                  recording.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Bubblegum Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPlaying
                      ? 'Playing • ${_RecordingPanel._formatDateTime(recording.lastModifiedTime)}'
                      : isActive
                      ? 'Paused • ${_RecordingPanel._formatDateTime(recording.lastModifiedTime)}'
                      : _RecordingPanel._formatDateTime(
                          recording.lastModifiedTime,
                        ),
                  style: const TextStyle(
                    fontFamily: 'Bubblegum Sans',
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month ${value.year} • $hour:$minute';
  }
}

class _AudioWaveform extends StatefulWidget {
  final bool isActive;
  final bool isPlaying;

  const _AudioWaveform({required this.isActive, required this.isPlaying});

  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isPlaying) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 30,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(9, (index) {
              final restingHeight = 7.0 + (index % 4) * 3.0;
              final wave = math.sin(
                (_controller.value * math.pi * 2) + (index * 0.8),
              );
              final height = widget.isPlaying
                  ? 8.0 + wave.abs() * 20.0
                  : restingHeight;

              return SizedBox(
                width: 3,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? AppColors.primary
                        : AppColors.subtle.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
