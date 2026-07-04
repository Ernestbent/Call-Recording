import 'package:flutter/material.dart';

class RecentCalls extends StatelessWidget {
  final String phoneNumber;
  final String timeInfo;
  final bool hasRecording;
  final VoidCallback? onPlayTap;

  const RecentCalls({
    super.key,
    required this.phoneNumber,
    required this.timeInfo,
    required this.hasRecording,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = hasRecording
        ? const Color(0xFFE17C0F)
        : const Color(0xFF8F867D);

    return Column(
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF554B42),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      phoneNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontFamily: 'Open Sans',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeInfo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'Open Sans',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              InkWell(
                onTap: hasRecording ? onPlayTap : null,
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    hasRecording
                        ? Icons.play_circle_fill_rounded
                        : Icons.schedule_rounded,
                    color: accentColor,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
