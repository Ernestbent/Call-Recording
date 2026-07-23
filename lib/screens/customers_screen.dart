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
      appBar: AppBar(title: const Text('Customers')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(
                    recordingsReadyCount: appState.recordingsReadyCount,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: appState.isFetchingAllRecordings
                          ? null
                          : () async {
                              final matches = await appState
                                  .fetchRecordingsForAllCustomers();

                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    matches == 0
                                        ? 'No customer recordings were found.'
                                        : 'Fetched recordings for $matches customer${matches == 1 ? '' : 's'}.',
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
                            ? 'Fetching recordings...'
                            : 'Fetch All Recordings',
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
                      '${appState.customers.length} contacts',
                      style: const TextStyle(
                        color: AppColors.subtle,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: appState.customers.isEmpty
                        ? const _EmptyCustomersState()
                        : ListView.separated(
                            itemCount: appState.customers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final customer = appState.customers[index];
                              return _CustomerCard(
                                customer: customer,
                                onCallTap: () async {
                                  final didOpen = await appState.dialCustomer(
                                    customer,
                                  );

                                  if (!context.mounted || didOpen) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to open dialer right now.',
                                      ),
                                    ),
                                  );
                                },
                                onPlayTap: customer.latestRecording == null
                                    ? null
                                    : () => appState.playRecording(
                                        customer.latestRecording!,
                                      ),
                              );
                            },
                          ),
                  ),
                ],
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
  const _EmptyCustomersState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppSurfaces.placeholder(radius: 16),
      child: const Row(
        children: [
          Icon(Icons.people_outline_rounded, color: AppColors.subtle, size: 22),
          SizedBox(width: 13),
          Expanded(
            child: Text(
              'Customer contacts will appear here when they are available.',
              style: TextStyle(
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

class _SummaryCard extends StatelessWidget {
  final int recordingsReadyCount;

  const _SummaryCard({required this.recordingsReadyCount});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    'RECORDINGS AVAILABLE',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$recordingsReadyCount',
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
                    'Customers ready to review',
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
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.asset(
                'lib/fonts/customer-service-headset.png',
                width: 25,
                height: 25,
                color: AppColors.primary,
                filterQuality: FilterQuality.high,
                semanticLabel: 'Customer service headset',
              ),
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
  final VoidCallback? onPlayTap;

  const _CustomerCard({
    required this.customer,
    required this.onCallTap,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: AppSurfaces.card(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    _initials(customer.name),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
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
              FilledButton(
                onPressed: onCallTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Call',
                  style: TextStyle(
                    fontFamily: 'Bubblegum Sans',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customer.matchingRecordingsCount > 0)
            Text(
              customer.matchingRecordingsCount == 1
                  ? 'Latest recording matched automatically'
                  : '${customer.matchingRecordingsCount} matching recordings found',
              style: const TextStyle(
                fontFamily: 'Bubblegum Sans',
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
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
          const SizedBox(height: 12),
          _RecordingPanel(
            recording: customer.latestRecording,
            lastCallStartedAt: customer.lastCallStartedAt,
            lastCallEndedAt: customer.lastCallEndedAt,
            onPlayTap: onPlayTap,
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _RecordingPanel extends StatelessWidget {
  final CallRecordingFile? recording;
  final DateTime? lastCallStartedAt;
  final DateTime? lastCallEndedAt;
  final VoidCallback? onPlayTap;

  const _RecordingPanel({
    required this.recording,
    required this.lastCallStartedAt,
    required this.lastCallEndedAt,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    if (recording == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppSurfaces.placeholder(radius: 12),
        child: Text(
          lastCallEndedAt == null
              ? 'Call a customer and the recording will appear here.'
              : 'Call started at ${_formatDateTime(lastCallStartedAt ?? lastCallEndedAt!)}. Last call ended at ${_formatDateTime(lastCallEndedAt!)}. No recording matched that call window.',
          style: const TextStyle(
            fontFamily: 'Bubblegum Sans',
            fontSize: 13,
            color: AppColors.muted,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppSurfaces.placeholder(radius: 12),
      child: Row(
        children: [
          InkWell(
            onTap: onPlayTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                  recording!.fileName,
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
                  _formatDateTime(recording!.lastModifiedTime),
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
