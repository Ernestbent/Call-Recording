import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/models/customer_contact.dart';
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
        centerTitle: true,
        toolbarHeight: 80,
        title: const Text(
          'Call Recorder',
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
            final recentCustomers = appState.customers
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
              padding: const EdgeInsets.all(20),
              children: [
                Container(
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
                        'Recordings Ready',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${appState.recordingsReadyCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 50,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'From Customer Calls',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: const [
                    Text(
                      'RECENT',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (recentCustomers.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: const Text(
                      'Customer recordings will appear here after calls are matched.',
                      style: TextStyle(
                        color: Color(0xFF7A7067),
                        fontSize: 13,
                        fontFamily: 'Open Sans',
                      ),
                    ),
                  )
                else
                  ...recentCustomers.take(5).map(
                    (customer) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
