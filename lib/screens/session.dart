import 'package:calls_recording/models/customer_contact.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
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
      _SessionFilter.pending => sessions
          .where((session) => session.status == _SessionStatus.pending)
          .toList(),
      _SessionFilter.uploaded => sessions
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
        centerTitle: true,
        toolbarHeight: 80,
        title: const Text(
          'All Sessions',
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF554B42)),
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
      body: Padding(
        padding: const EdgeInsets.all(20),
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
                  onTap: () => setState(() => _selectedFilter = _SessionFilter.all),
                ),
                _FilterChipButton(
                  label: 'Pending ($pendingCount)',
                  selected: _selectedFilter == _SessionFilter.pending,
                  onTap: () =>
                      setState(() => _selectedFilter = _SessionFilter.pending),
                ),
                _FilterChipButton(
                  label: 'Uploaded ($uploadedCount)',
                  selected: _selectedFilter == _SessionFilter.uploaded,
                  onTap: () =>
                      setState(() => _selectedFilter = _SessionFilter.uploaded),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 2,
        appState: widget.appState,
        onTap: (_) {},
      ),
    );
  }

  List<_SessionItem> _buildSessionItems(List<CustomerContact> customers) {
    final items = customers
        .where(
          (customer) =>
              customer.lastCallStartedAt != null || customer.lastCallEndedAt != null,
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
        final aTime = a.endedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.endedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFFE17C0F) : const Color(0xFFF2EDE8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: highlighted ? Colors.white : const Color(0xFF554B42),
              fontSize: 13,
              fontFamily: 'Open Sans',
              fontWeight: FontWeight.w600,
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
    final statusColor = isPending ? const Color(0xFFE17C0F) : const Color(0xFF2E8B57);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF554B42),
                    fontFamily: 'Open Sans',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  session.phoneNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7A7067),
                    fontFamily: 'Open Sans',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  session.metaLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8F867D),
                    fontFamily: 'Open Sans',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              session.statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: statusColor,
                fontFamily: 'Open Sans',
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: const Text(
        'Call sessions will appear here after customer calls are tracked.',
        style: TextStyle(
          color: Color(0xFF7A7067),
          fontSize: 13,
          fontFamily: 'Open Sans',
        ),
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

  String get statusLabel => status == _SessionStatus.pending ? 'Pending' : 'Uploaded';

  String get metaLine {
    final callStamp = startedAt ?? endedAt;
    final callTime = callStamp == null ? 'No call time saved' : _formatDate(callStamp);
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
