import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/models/persisted_call_session.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:calls_recording/widgets/recent_calls.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final CustomerCallStore appState;

  const HomeScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Recorder')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final recentCutoff = DateTime.now().subtract(
              const Duration(days: 7),
            );
            final recentSessions = appState.callSessions
                .where((session) => !session.startedAt.isBefore(recentCutoff))
                .take(5)
                .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              children: [
                _RecordingsOverview(count: appState.recordingsReadyCount),
                const SizedBox(height: 28),
                SectionLabel(
                  'Recent activity',
                  trailing: Text(
                    recentSessions.isEmpty
                        ? 'No calls yet'
                        : 'Latest ${recentSessions.length}',
                    style: const TextStyle(
                      color: AppColors.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (recentSessions.isEmpty)
                  const _EmptyRecentState()
                else
                  ...recentSessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RecentCalls(
                        phoneNumber: session.customerName,
                        timeInfo: _buildRecentSubtitle(session),
                        hasRecording: session.recording != null,
                        isPlaying:
                            session.recording != null &&
                            appState.isPlayingRecording(session.recording!),
                        onPlayTap: session.recording == null
                            ? null
                            : () async {
                                final didStart = await appState.playRecording(
                                  session.recording!,
                                );
                                if (!context.mounted || didStart) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Unable to play this recording.',
                                    ),
                                  ),
                                );
                              },
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

  static String _buildRecentSubtitle(PersistedCallSession session) {
    final timeLabel =
        '${session.phoneNumber} • ${_formatTime(session.startedAt)}';
    return switch (session.status) {
      PersistedCallStatus.waitingForRecording =>
        '$timeLabel • Waiting for recording',
      PersistedCallStatus.recordingNotFound =>
        '$timeLabel • Recording not found',
      PersistedCallStatus.pendingUpload => '$timeLabel • Pending upload',
      PersistedCallStatus.uploaded => '$timeLabel • Uploaded',
    };
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
          Image.asset(
            'lib/images/microphone.png',
            width: 54,
            height: 54,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Microphone',
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
