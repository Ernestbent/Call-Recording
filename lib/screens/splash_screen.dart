import 'dart:async';

import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:calls_recording/services/secure_session_storage.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final CustomerCallStore appState;
  final ErpNextAuthenticator? erpNextAuthenticator;
  final SessionStorage? sessionStorage;
  final AgentCredentialManager? credentialManager;

  const SplashScreen({
    super.key,
    required this.appState,
    this.erpNextAuthenticator,
    this.sessionStorage,
    this.credentialManager,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _imageScale;
  late final ErpNextAuthenticator _erpNextAuthenticator;
  late final SessionStorage _sessionStorage;
  late final AgentCredentialManager _credentialManager;
  late final Future<ErpNextSession?> _savedSession;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _erpNextAuthenticator = widget.erpNextAuthenticator ?? ErpNextAuthService();
    _sessionStorage = widget.sessionStorage ?? SecureSessionStorage();
    _credentialManager =
        widget.credentialManager ?? SecureAgentCredentialManager();
    _savedSession = _readValidSavedSession();
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

  Future<ErpNextSession?> _readValidSavedSession() async {
    try {
      final session = await _sessionStorage.read();
      if (session == null) {
        await _credentialManager.clear();
        return null;
      }

      final isValid = await _erpNextAuthenticator.isSessionValid(session);
      if (!isValid) {
        await _sessionStorage.clear();
        await _credentialManager.clear();
        return null;
      }

      final activeCredentials = await _credentialManager.read();
      if (activeCredentials == null ||
          !activeCredentials.belongsTo(session.userId)) {
        await _credentialManager.activateForEmail(session.userId);
      }
      return session;
    } catch (_) {
      try {
        await _sessionStorage.clear();
        await _credentialManager.clear();
      } catch (_) {
        // The login screen remains the safe fallback.
      }
      return null;
    }
  }

  Future<void> _openApp() async {
    final session = await _savedSession;
    if (session != null) {
      await widget.appState.loadDraftPaymentCustomers(session);
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, secondaryAnimation) => session != null
            ? HomeScreen(appState: widget.appState)
            : LoginScreen(
                appState: widget.appState,
                erpNextAuthenticator: _erpNextAuthenticator,
                sessionStorage: _sessionStorage,
                credentialManager: _credentialManager,
              ),
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
