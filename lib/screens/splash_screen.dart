import 'dart:async';

import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/company_logo.dart';
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
  late final Animation<double> _contentOpacity;
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
    _contentOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.55, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    _navigationTimer = Timer(const Duration(milliseconds: 3200), _openApp);
  }

  void _openApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, secondaryAnimation) =>
            HomeScreen(appState: widget.appState),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: AnimatedBuilder(
              animation: _imageScale,
              builder: (context, child) {
                return Transform.scale(scale: _imageScale.value, child: child);
              },
              child: Image.asset(
                'lib/images/Logo.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(0.55, 0),
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(color: AppColors.darkSurface);
                },
              ),
            ),
          ),
          ColoredBox(color: AppColors.darkSurface.withValues(alpha: 0.12)),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: FadeTransition(
                  opacity: _contentOpacity,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            CompanyLogo(
                              width: 88,
                              height: 54,
                              borderRadius: 10,
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Call Recorder',
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Every conversation, organised.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: _controller.value,
                                minHeight: 4,
                                backgroundColor: AppColors.primarySoft,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
