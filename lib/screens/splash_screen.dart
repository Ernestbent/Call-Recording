import 'dart:async';

import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final CustomerCallStore appState;

  const SplashScreen({super.key, required this.appState});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _imageScale;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    );
    _imageScale = Tween<double>(
      begin: 1.05,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));
    _controller.forward();
    _navigationTimer = Timer(const Duration(milliseconds: 3200), _openApp);
  }

  void _openApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, secondaryAnimation) =>
            LoginScreen(appState: widget.appState),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: fade, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSurface,
      body: ClipRect(
        child: AnimatedBuilder(
          animation: _imageScale,
          builder: (context, child) {
            return Transform.scale(scale: _imageScale.value, child: child);
          },
          child: Image.asset(
            'lib/images/Logo.jpg',
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            alignment: const Alignment(0.55, 0),
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: AppColors.darkSurface);
            },
          ),
        ),
      ),
    );
  }
}
