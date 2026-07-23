import 'package:calls_recording/screens/customers_screen.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/screens/session.dart';
import 'package:calls_recording/screens/settings.dart';
import 'package:calls_recording/theme/app_theme.dart';

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
    required IconData iconData,
    required int index,
    required BuildContext context,
  }) {
    final isActive = widget.currentIndex == index;
    final isHovered = _hoveredIndex == index;
    final isHighlighted = isActive || isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _handleTap(index, context),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconData,
                size: 23,
                color: isHighlighted ? AppColors.primary : AppColors.subtle,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isHighlighted ? AppColors.primary : AppColors.muted,
                  fontWeight: FontWeight.w400,
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
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        10,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.navigation,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildItem(
            label: "Home",
            iconData: widget.currentIndex == 0
                ? Icons.home_rounded
                : Icons.home_outlined,
            index: 0,
            context: context,
          ),
          _buildItem(
            label: "Customers",
            iconData: widget.currentIndex == 1
                ? Icons.people_alt_rounded
                : Icons.people_alt_outlined,
            index: 1,
            context: context,
          ),
          _buildItem(
            label: "Sessions",
            iconData: widget.currentIndex == 2
                ? Icons.view_timeline_rounded
                : Icons.view_timeline_outlined,
            index: 2,
            context: context,
          ),
          _buildItem(
            label: "Settings",
            iconData: widget.currentIndex == 3
                ? Icons.settings_rounded
                : Icons.settings_outlined,
            index: 3,
            context: context,
          ),
        ],
      ),
    );
  }
}
