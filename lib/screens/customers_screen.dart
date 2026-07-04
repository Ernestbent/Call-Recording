import 'package:calls_recording/models/call_recording_file.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:flutter/material.dart';

class CustomersScreen extends StatelessWidget {
  final CustomerCallStore appState;

  const CustomersScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 80,
        title: const Text(
          'Customers',
          style: TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Color(0xFF554B42),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: Color(0xFFD9D9D9), thickness: 1, height: 1),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.all(20),
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
                              final matches =
                                  await appState.fetchRecordingsForAllCustomers();

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
                        backgroundColor: const Color(0xFF554B42),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFB5ACA4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                          fontFamily: 'Open Sans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'CUSTOMER CALLS',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: appState.customers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
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

class _SummaryCard extends StatelessWidget {
  final int recordingsReadyCount;

  const _SummaryCard({required this.recordingsReadyCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 164,
      decoration: BoxDecoration(
        color: const Color(0xFFE17C0F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Text(
            'Customers Ready',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '$recordingsReadyCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 50,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Recordings Available',
            style: TextStyle(color: Colors.white, fontSize: 18),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _initials(customer.name),
                    style: const TextStyle(
                      color: Color(0xFFE17C0F),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
                        fontFamily: 'Open Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF554B42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.phoneNumber,
                      style: const TextStyle(
                        fontFamily: 'Open Sans',
                        fontSize: 13,
                        color: Color(0xFF7A7067),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.subtitle,
                      style: const TextStyle(
                        fontFamily: 'Open Sans',
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onCallTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE17C0F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Call',
                  style: TextStyle(
                    fontFamily: 'Open Sans',
                    fontWeight: FontWeight.w600,
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
                fontFamily: 'Open Sans',
                fontSize: 12,
                color: Color(0xFF7A7067),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F6F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  customer.isCallInProgress
                      ? Icons.phone_in_talk_rounded
                      : Icons.fiber_manual_record_rounded,
                  size: 16,
                  color: customer.isCallInProgress
                      ? const Color(0xFFE17C0F)
                      : const Color(0xFF8F867D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customer.statusLabel,
                    style: const TextStyle(
                      fontFamily: 'Open Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF554B42),
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
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF0E1D1)),
        ),
        child: Text(
          lastCallEndedAt == null
              ? 'Call a customer and the recording will appear here.'
              : 'Call started at ${_formatDateTime(lastCallStartedAt ?? lastCallEndedAt!)}. Last call ended at ${_formatDateTime(lastCallEndedAt!)}. No recording matched that call window.',
          style: const TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 13,
            color: Color(0xFF7A7067),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF554B42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onPlayTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFE17C0F),
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
                      fontFamily: 'Open Sans',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                if (lastCallStartedAt != null) const SizedBox(height: 4),
                Text(
                  recording!.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Open Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(recording!.lastModifiedTime),
                  style: const TextStyle(
                    fontFamily: 'Open Sans',
                    fontSize: 12,
                    color: Colors.white70,
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
