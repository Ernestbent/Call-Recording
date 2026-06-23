import 'package:flutter/material.dart';

class RecentCalls extends StatelessWidget {
  final String phoneNumber;
  final String timeInfo;
  final String imagePath;

  const RecentCalls({
    super.key,
    required this.phoneNumber,
    required this.timeInfo,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF554B42),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    phoneNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    timeInfo,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              Image.asset(
                imagePath,
                width: 30,
                height: 30,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
