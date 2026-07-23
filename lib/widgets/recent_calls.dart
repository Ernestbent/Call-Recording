import 'package:flutter/material.dart';
import 'package:calls_recording/theme/app_theme.dart';

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
    final accentColor = hasRecording ? AppColors.primary : AppColors.subtle;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(16),
      decoration: AppSurfaces.card(radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: hasRecording
                  ? AppColors.primarySoft
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              hasRecording ? Icons.graphic_eq_rounded : Icons.schedule_rounded,
              color: accentColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontFamily: 'Bubblegum Sans',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  timeInfo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
                    fontFamily: 'Bubblegum Sans',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: hasRecording ? AppColors.primary : AppColors.surfaceMuted,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: hasRecording ? onPlayTap : null,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  hasRecording
                      ? Icons.play_arrow_rounded
                      : Icons.more_horiz_rounded,
                  color: hasRecording ? Colors.white : accentColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
