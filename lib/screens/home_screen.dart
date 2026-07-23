import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/company_logo.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:calls_recording/widgets/recent_calls.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final CustomerCallStore appState;

  const HomeScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            CompanyLogo(width: 54, height: 38),
            SizedBox(width: 12),
            Text('Call Recorder'),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final recentCustomers =
                appState.customers
                    .where(
                      (customer) =>
                          customer.lastCallEndedAt != null ||
                          customer.latestRecording != null,
                    )
                    .toList()
                  ..sort((a, b) {
                    final aTime =
                        a.lastCallEndedAt ??
                        a.latestRecording?.lastModifiedTime ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    final bTime =
                        b.lastCallEndedAt ??
                        b.latestRecording?.lastModifiedTime ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    return bTime.compareTo(aTime);
                  });

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              children: [
                _RecordingsOverview(count: appState.recordingsReadyCount),
                const SizedBox(height: 28),
                SectionLabel(
                  'Recent activity',
                  trailing: Text(
                    recentCustomers.isEmpty
                        ? 'No calls yet'
                        : '${recentCustomers.length} total',
                    style: const TextStyle(
                      color: AppColors.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (recentCustomers.isEmpty)
                  const _EmptyRecentState()
                else
                  ...recentCustomers
                      .take(5)
                      .map(
                        (customer) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RecentCalls(
                            phoneNumber: customer.name,
                            timeInfo: _buildRecentSubtitle(customer),
                            hasRecording: customer.latestRecording != null,
                            onPlayTap: customer.latestRecording == null
                                ? null
                                : () => appState.playRecording(
                                    customer.latestRecording!,
                                  ),
                          ),
                        ),
                      ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 0,
        appState: appState,
        onTap: (_) {},
      ),
    );
  }

  static String _buildRecentSubtitle(CustomerContact customer) {
    final callTime =
        customer.lastCallStartedAt ??
        customer.lastCallEndedAt ??
        customer.latestRecording?.lastModifiedTime;

    final timeLabel = callTime == null
        ? customer.phoneNumber
        : '${customer.phoneNumber} • ${_formatTime(callTime)}';

    if (customer.latestRecording == null) {
      return '$timeLabel • Waiting for matching recording';
    }

    return '$timeLabel • ${customer.latestRecording!.fileName}';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _RecordingsOverview extends StatelessWidget {
  final int count;

  const _RecordingsOverview({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(20),
      decoration: AppSurfaces.card(radius: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RECORDINGS READY',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$count',
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
                  'From customer calls',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: AppColors.primary,
              size: 25,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecentState extends StatelessWidget {
  const _EmptyRecentState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: AppSurfaces.placeholder(radius: 16),
      child: const Row(
        children: [
          _EmptyIcon(),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your activity starts here',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Matched customer recordings will appear after a call.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyIcon extends StatelessWidget {
  const _EmptyIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 46,
        height: 46,
        child: Icon(Icons.waves_rounded, color: AppColors.primary, size: 23),
      ),
    );
  }
}
