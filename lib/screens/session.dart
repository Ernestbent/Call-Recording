import 'package:flutter/material.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart'; // Import the navbar

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  int currentIndex = 1; // Set to 1 for Sessions tab

  @override
  Widget build(BuildContext context) {
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
        // Add back button to return to Home
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF554B42)),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter buttons - evenly spaced
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // All button
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE17C0F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'All (10)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Open Sans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Pending button
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF554B42),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'Pending (4)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Open Sans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Uploaded button
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF554B42),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'Uploaded (6)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Open Sans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Sessions list with sample data
            const Expanded(
              child: SessionsList(),
            ),
          ],
        ),
      ),
      // Add bottom navigation bar
      bottomNavigationBar: CustomBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 0) {
            // Go back to Home
            Navigator.pop(context);
          } else if (index == 2) {
            // Navigate to Settings - you can add this later
            // For now, just show a message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Settings coming soon!'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          // If index == 1 (Sessions), we're already here
        },
      ),
    );
  }
}

// Sessions List Widget
class SessionsList extends StatelessWidget {
  const SessionsList({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample session data - added 2 more cards
    final List<Map<String, String>> sessions = [
      {
        'phone': '+256 757001909',
        'date': '2024-01-15',
        'duration': '5m 14s',
        'status': 'Pending'
      },
      {
        'phone': '+256 72545948',
        'date': '2024-01-15',
        'duration': '10m 14s',
        'status': 'Synced'
      },
      {
        'phone': '+256 772835195',
        'date': '2024-01-14',
        'duration': '3m 22s',
        'status': 'Pending'
      },
      {
        'phone': '+256 701234567',
        'date': '2024-01-14',
        'duration': '7m 45s',
        'status': 'Synced'
      },
      // NEW CARD 1
      {
        'phone': '+256 788901234',
        'date': '2024-01-13',
        'duration': '2m 30s',
        'status': 'Pending'
      },
      // NEW CARD 2
      {
        'phone': '+256 712345678',
        'date': '2024-01-13',
        'duration': '15m 20s',
        'status': 'Synced'
      },
      // NEW CARD 3 (Optional - added one more for good measure)
      {
        'phone': '+256 756789012',
        'date': '2024-01-12',
        'duration': '8m 45s',
        'status': 'Synced'
      },
    ];

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isPending = session['status'] == 'Pending';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side: session details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['phone']!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF554B42),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${session['date']} • ${session['duration']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // Right side: status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  session['status']!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPending ? Colors.orange : Colors.green,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}