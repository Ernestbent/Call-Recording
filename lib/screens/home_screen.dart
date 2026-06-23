import 'package:flutter/material.dart';
import 'package:calls_recording/widgets/recent_calls.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;

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
          child: Divider(
            color: Color(0xFFD9D9D9),
            thickness: 1,
            height: 1,
          ),
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // TOP SUMMARY CARD
              Container(
                width: double.infinity,
                height: 164,
                decoration: BoxDecoration(
                  color: const Color(0xFFE17C0F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      'Pending Uploads',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Ready To Sync',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // RECENT TITLE
              Row(
                children: [
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

              // CALL LIST
              const RecentCalls(
                phoneNumber: '+256 757001909',
                timeInfo: '14:57 • 5m 14s',
                imagePath: 'lib/images/pending.png',
              ),
              const RecentCalls(
                phoneNumber: '+256 72545948',
                timeInfo: '12:27 • 10m 14s',
                imagePath: 'lib/images/checklist.png',
              ),
              const RecentCalls(
                phoneNumber: '+256 772835195',
                timeInfo: '17:57 • 5m 14s',
                imagePath: 'lib/images/alert.png',
              ),
            ],
          ),
        ),
      ),

      // 👇 BOTTOM NAV BAR ADDED HERE
      bottomNavigationBar: CustomBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });
        },
      ),
    );
  }
}