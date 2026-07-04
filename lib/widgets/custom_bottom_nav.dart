import 'package:calls_recording/screens/customers_screen.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/screens/session.dart';
import 'package:calls_recording/screens/settings.dart';

class CustomBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final CustomerCallStore appState;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.appState,
  });

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  int _hoveredIndex = -1;

  void _handleTap(int index, BuildContext context) {
    if (index == widget.currentIndex) {
      widget.onTap(index);
      return;
    }

    final destination = switch (index) {
      0 => HomeScreen(appState: widget.appState),
      1 => CustomersScreen(appState: widget.appState),
      2 => SessionsScreen(appState: widget.appState),
      3 => SettingsScreen(appState: widget.appState),
      _ => null,
    };

    if (destination == null) {
      widget.onTap(index);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );

    widget.onTap(index);
  }

  Widget _buildItem({
    required String label,
    String? iconPath,
    IconData? iconData,
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
        splashColor: Colors.orange.withValues(alpha: 0.2),
        highlightColor: Colors.orange.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconPath != null)
                Image.asset(
                  iconPath,
                  width: 26,
                  height: 26,
                  color: isOrange ? Colors.orange : Colors.grey,
                )
              else if (iconData != null)
                Icon(
                  iconData,
                  size: 26,
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
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildItem(
            label: "Home",
            iconData: Icons.home_outlined,
            index: 0,
            context: context,
          ),
          _buildItem(
            label: "Customers",
            iconData: Icons.person_outline_rounded,
            index: 1,
            context: context,
          ),
          _buildItem(
            label: "Sessions",
            iconData: Icons.checklist_rounded,
            index: 2,
            context: context,
          ),
          _buildItem(
            label: "Settings",
            iconData: Icons.settings_outlined,
            index: 3,
            context: context,
          ),
        ],
      ),
    );
  }
}
