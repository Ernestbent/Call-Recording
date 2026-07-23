import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:flutter/material.dart';

enum _SessionFilter { all, pending, uploaded }

class SessionsScreen extends StatefulWidget {
  final CustomerCallStore appState;

  const SessionsScreen({super.key, required this.appState});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  _SessionFilter _selectedFilter = _SessionFilter.all;

  @override
  Widget build(BuildContext context) {
    final sessions = _buildSessionItems(widget.appState.customers);
    final filteredSessions = switch (_selectedFilter) {
      _SessionFilter.all => sessions,
      _SessionFilter.pending =>
        sessions
            .where((session) => session.status == _SessionStatus.pending)
            .toList(),
      _SessionFilter.uploaded =>
        sessions
            .where((session) => session.status == _SessionStatus.uploaded)
            .toList(),
    };

    final pendingCount = sessions
        .where((session) => session.status == _SessionStatus.pending)
        .length;
    final uploadedCount = sessions
        .where((session) => session.status == _SessionStatus.uploaded)
        .length;

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
                    label: 'All (${sessions.length})',
                    selected: _selectedFilter == _SessionFilter.all,
                    onTap: () =>
                        setState(() => _selectedFilter = _SessionFilter.all),
                  ),
                  _FilterChipButton(
                    label: 'Pending ($pendingCount)',
                    selected: _selectedFilter == _SessionFilter.pending,
                    onTap: () => setState(
                      () => _selectedFilter = _SessionFilter.pending,
                    ),
                  ),
                  _FilterChipButton(
                    label: 'Uploaded ($uploadedCount)',
                    selected: _selectedFilter == _SessionFilter.uploaded,
                    onTap: () => setState(
                      () => _selectedFilter = _SessionFilter.uploaded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionLabel(
                _selectedFilter == _SessionFilter.all
                    ? 'All sessions'
                    : _selectedFilter == _SessionFilter.pending
                    ? 'Awaiting recording'
                    : 'Ready to review',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredSessions.isEmpty
                    ? const _EmptySessionsState()
                    : ListView.separated(
                        itemCount: filteredSessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final session = filteredSessions[index];
                          return _SessionCard(session: session);
                        },
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
  }

  List<_SessionItem> _buildSessionItems(List<CustomerContact> customers) {
    final items =
        customers
            .where(
              (customer) =>
                  customer.lastCallStartedAt != null ||
                  customer.lastCallEndedAt != null,
            )
            .map((customer) {
              final startedAt = customer.lastCallStartedAt;
              final endedAt = customer.lastCallEndedAt;
              final status = customer.latestRecording != null
                  ? _SessionStatus.uploaded
                  : _SessionStatus.pending;

              return _SessionItem(
                name: customer.name,
                phoneNumber: customer.phoneNumber,
                startedAt: startedAt,
                endedAt: endedAt,
                status: status,
              );
            })
            .toList()
          ..sort((a, b) {
            final aTime =
                a.endedAt ??
                a.startedAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                b.endedAt ??
                b.startedAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

    return items;
  }
}

class _FilterChipButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FilterChipButton> createState() => _FilterChipButtonState();
}

class _FilterChipButtonState extends State<_FilterChipButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.primary : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: highlighted ? Colors.white : AppColors.muted,
              fontSize: 12,
              fontFamily: 'Bubblegum Sans',
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final _SessionItem session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final isPending = session.status == _SessionStatus.pending;
    final statusColor = isPending ? AppColors.warning : AppColors.success;
    final statusBackground = isPending
        ? AppColors.warningSoft
        : AppColors.successSoft;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: AppSurfaces.card(radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isPending ? Icons.schedule_rounded : Icons.cloud_done_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
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
                  session.metaLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.subtle,
                    fontFamily: 'Bubblegum Sans',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              session.statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: statusColor,
                fontFamily: 'Bubblegum Sans',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySessionsState extends StatelessWidget {
  const _EmptySessionsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppSurfaces.placeholder(radius: 16),
      child: const Row(
        children: [
          Icon(Icons.history_rounded, color: AppColors.subtle),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Call sessions will appear here after customer calls are tracked.',
              style: TextStyle(
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

enum _SessionStatus { pending, uploaded }

class _SessionItem {
  final String name;
  final String phoneNumber;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final _SessionStatus status;

  const _SessionItem({
    required this.name,
    required this.phoneNumber,
    required this.startedAt,
    required this.endedAt,
    required this.status,
  });

  String get statusLabel =>
      status == _SessionStatus.pending ? 'Pending' : 'Uploaded';

  String get metaLine {
    final callStamp = startedAt ?? endedAt;
    final callTime = callStamp == null
        ? 'No call time saved'
        : _formatDate(callStamp);
    if (startedAt == null || endedAt == null) {
      return callTime;
    }

    final duration = endedAt!.difference(startedAt!);
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
