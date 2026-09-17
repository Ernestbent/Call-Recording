import 'package:calls_recording/models/persisted_call_session.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:flutter/material.dart';

enum _SessionFilter { active, history }

class SessionsScreen extends StatefulWidget {
  final CustomerCallStore appState;

  const SessionsScreen({super.key, required this.appState});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  static const int _historyPageSize = 20;

  _SessionFilter _selectedFilter = _SessionFilter.active;
  int _visibleHistoryCount = _historyPageSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final activeSessions = widget.appState.activeCallSessions;
        final history = widget.appState.sessionHistory;
        final selectedSessions = _selectedFilter == _SessionFilter.active
            ? activeSessions
            : history.take(_visibleHistoryCount).toList(growable: false);
        final hasMoreHistory = history.length > selectedSessions.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Sessions'),
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeScreen(appState: widget.appState),
                  ),
                );
              },
            ),
            actions: [
              if (_selectedFilter == _SessionFilter.history &&
                  history.isNotEmpty)
                IconButton(
                  key: const Key('clear-session-history-button'),
                  tooltip: 'Clear history',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _confirmClearHistory,
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _FilterChipButton(
                        label: 'Active (${activeSessions.length})',
                        selected: _selectedFilter == _SessionFilter.active,
                        onTap: () => setState(
                          () => _selectedFilter = _SessionFilter.active,
                        ),
                      ),
                      _FilterChipButton(
                        label: 'History (${history.length})',
                        selected: _selectedFilter == _SessionFilter.history,
                        onTap: () => setState(() {
                          _selectedFilter = _SessionFilter.history;
                          _visibleHistoryCount = _historyPageSize;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SectionLabel(
                    _selectedFilter == _SessionFilter.active
                        ? 'Needs attention'
                        : 'Uploaded and unavailable',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: selectedSessions.isEmpty
                        ? _EmptySessionsState(filter: _selectedFilter)
                        : ListView(
                            children: [
                              for (final session in selectedSessions) ...[
                                _SessionCard(
                                  session: session,
                                  onRescan:
                                      session.status ==
                                          PersistedCallStatus.recordingNotFound
                                      ? () => _rescan(session)
                                      : null,
                                  onDelete:
                                      _selectedFilter == _SessionFilter.history
                                      ? () => _confirmDeleteSession(session)
                                      : null,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (hasMoreHistory)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: OutlinedButton.icon(
                                    key: const Key('load-more-session-history'),
                                    onPressed: () => setState(
                                      () => _visibleHistoryCount +=
                                          _historyPageSize,
                                    ),
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text('Load more history'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: CustomBottomNav(
            currentIndex: 2,
            appState: widget.appState,
            onTap: (_) {},
          ),
        );
      },
    );
  }

  Future<void> _rescan(PersistedCallSession session) async {
    final found = await widget.appState.rescanSession(session.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          found
              ? 'Recording found and queued for upload.'
              : 'No matching recording was found.',
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear session history?'),
        content: const Text(
          'This removes uploaded and unavailable session entries from this '
          'phone. Server records and audio files are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-clear-session-history'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = await widget.appState.clearResolvedSessionHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $removed session entries.')),
    );
  }

  Future<void> _confirmDeleteSession(PersistedCallSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this session?'),
        content: const Text(
          'Only the local session entry is removed. The server record and '
          'audio file remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.appState.deleteResolvedSession(session.id);
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.muted,
            fontSize: 12,
            fontFamily: 'Bubblegum Sans',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final PersistedCallSession session;
  final VoidCallback? onRescan;
  final VoidCallback? onDelete;

  const _SessionCard({
    required this.session,
    required this.onRescan,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final style = _SessionStyle.forStatus(session.status);

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: AppSurfaces.card(radius: 16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(style.icon, color: style.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                        fontFamily: 'Bubblegum Sans',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.phoneNumber,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        fontFamily: 'Bubblegum Sans',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _metaLine(session),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.subtle,
                        fontFamily: 'Bubblegum Sans',
                      ),
                    ),
                    if (session.lastError?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      Text(
                        session.lastError!.trim(),
                        key: Key('session-error-${session.id}'),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: AppColors.warning,
                          fontFamily: 'Bubblegum Sans',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: style.color,
                    fontFamily: 'Bubblegum Sans',
                  ),
                ),
              ),
            ],
          ),
          if (onRescan != null || onDelete != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onRescan != null)
                  TextButton.icon(
                    onPressed: onRescan,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Rescan'),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remove local session',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _metaLine(PersistedCallSession session) {
    final callTime = _formatDate(session.startedAt);
    final endedAt = session.endedAt;
    if (endedAt == null) return callTime;

    final duration = endedAt.difference(session.startedAt);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$callTime • ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year} • $hour:$minute';
  }
}

class _SessionStyle {
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  const _SessionStyle({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  factory _SessionStyle.forStatus(PersistedCallStatus status) {
    return switch (status) {
      PersistedCallStatus.waitingForRecording => const _SessionStyle(
        label: 'Waiting',
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        background: AppColors.warningSoft,
      ),
      PersistedCallStatus.recordingNotFound => const _SessionStyle(
        label: 'Unavailable',
        icon: Icons.mic_off_outlined,
        color: AppColors.muted,
        background: AppColors.surfaceMuted,
      ),
      PersistedCallStatus.pendingUpload => const _SessionStyle(
        label: 'Pending upload',
        icon: Icons.cloud_upload_outlined,
        color: AppColors.warning,
        background: AppColors.warningSoft,
      ),
      PersistedCallStatus.uploaded => const _SessionStyle(
        label: 'Uploaded',
        icon: Icons.cloud_done_rounded,
        color: AppColors.success,
        background: AppColors.successSoft,
      ),
    };
  }
}

class _EmptySessionsState extends StatelessWidget {
  final _SessionFilter filter;

  const _EmptySessionsState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppSurfaces.placeholder(radius: 16),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: AppColors.subtle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filter == _SessionFilter.active
                  ? 'No calls are waiting for a recording or upload.'
                  : 'Uploaded and unavailable sessions will appear here.',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.4,
                fontFamily: 'Bubblegum Sans',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
