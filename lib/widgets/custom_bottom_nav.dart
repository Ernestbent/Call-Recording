import 'package:flutter/material.dart';
import 'package:calls_recording/screens/session.dart';
import 'package:calls_recording/screens/settings.dart'; // Import Settings

class CustomBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  int _hoveredIndex = -1;

  void _handleTap(int index, BuildContext context) {
    if (index == 1) {
      // Navigate to Sessions screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SessionsScreen(),
        ),
      );
    } else if (index == 2) {
      // Navigate to Settings screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SettingsScreen(),
        ),
      );
    } else {
      // For Home (0), use the regular onTap
      widget.onTap(index);
    }
  }

  Widget _buildItem({
    required String label,
    required String iconPath,
    required int index,
    required BuildContext context,
  }) {
    final isActive = widget.currentIndex == index;
    final isHovered = _hoveredIndex == index;
    final isOrange = isActive || isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _handleTap(index, context),
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.orange.withOpacity(0.2),
        highlightColor: Colors.orange.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                iconPath,
                width: 26,
                height: 26,
                color: isOrange ? Colors.orange : Colors.grey,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isOrange ? Colors.orange : Colors.grey,
                  fontWeight: isOrange ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildItem(
            label: "Home",
            iconPath: "lib/images/home.png",
            index: 0,
            context: context,
          ),
          _buildItem(
            label: "Sessions",
            iconPath: "lib/images/menu.png",
            index: 1,
            context: context,
          ),
          _buildItem(
            label: "Settings",
            iconPath: "lib/images/settings.png",
            index: 2,
            context: context,
          ),
        ],
      ),
    );
  }
}