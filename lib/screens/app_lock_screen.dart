import 'dart:async';

import 'package:calls_recording/services/app_lock_service.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pattern_lock/pattern_lock.dart';

class AppLockScreen extends StatefulWidget {
  final AppLockService appLockService;
  final bool biometricsEnabled;
  final VoidCallback onUnlocked;
  final ValueChanged<bool>? onBiometricAuthenticationChanged;

  const AppLockScreen({
    super.key,
    required this.appLockService,
    required this.biometricsEnabled,
    required this.onUnlocked,
    this.onBiometricAuthenticationChanged,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  List<BiometricType> _availableBiometrics = const [];
  bool _isLoadingBiometrics = true;
  bool _showPattern = false;
  bool _isAuthenticating = false;
  bool _isCheckingPattern = false;
  String? _message;
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  bool get _canUseBiometrics =>
      widget.biometricsEnabled && _availableBiometrics.isNotEmpty;

  String get _biometricLabel {
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    }
    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face unlock';
    }
    return 'Fingerprint';
  }

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
  }

  Future<void> _loadBiometrics() async {
    if (!widget.biometricsEnabled) {
      if (mounted) {
        setState(() {
          _isLoadingBiometrics = false;
        });
      }
      return;
    }
    final available = await widget.appLockService.availableBiometrics();
    if (!mounted) return;
    setState(() {
      _availableBiometrics = available;
      _isLoadingBiometrics = false;
    });
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isAuthenticating || !_canUseBiometrics) return;

    setState(() {
      _isAuthenticating = true;
      _showPattern = false;
      _message = null;
    });
    widget.onBiometricAuthenticationChanged?.call(true);
    final authenticated = await widget.appLockService
        .authenticateWithBiometrics();
    widget.onBiometricAuthenticationChanged?.call(false);
    if (!mounted) return;

    if (authenticated) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _isAuthenticating = false;
      _message =
          'Fingerprint unlock was not completed. Try again or use your pattern.';
    });
  }

  void _selectPattern() {
    setState(() {
      _showPattern = true;
      _message = null;
    });
  }

  void _showMethodChoices() {
    setState(() {
      _showPattern = false;
      _message = null;
    });
  }

  Future<void> _checkPattern(List<int> pattern) async {
    if (_isCheckingPattern || _lockoutSeconds > 0) return;

    setState(() {
      _isCheckingPattern = true;
      _message = null;
    });
    final matches = await widget.appLockService.verifyPattern(pattern);
    if (!mounted) return;

    if (matches) {
      widget.onUnlocked();
      return;
    }

    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _beginLockout();
    } else {
      setState(() {
        _isCheckingPattern = false;
        _message = 'Wrong pattern. ${5 - _failedAttempts} attempts remaining.';
      });
    }
  }

  void _beginLockout() {
    _lockoutTimer?.cancel();
    setState(() {
      _isCheckingPattern = false;
      _lockoutSeconds = 30;
      _message = 'Too many attempts. Try again in 30 seconds.';
    });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _failedAttempts = 0;
          _lockoutSeconds = 0;
          _message = null;
        });
      } else {
        setState(() {
          _lockoutSeconds--;
          _message =
              'Too many attempts. Try again in $_lockoutSeconds seconds.';
        });
      }
    });
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    SizedBox(
                      width: 210,
                      height: 118,
                      child: Image.asset(
                        'lib/images/ChatGPT Image Jul 23, 2026, 12_41_12 PM.png',
                        key: const Key('autozone-lock-logo'),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Select to Unlock App',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _showPattern
                          ? 'Draw your app pattern to continue.'
                          : 'Choose how you want to unlock the app.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (!_showPattern) ...[
                      _buildUnlockMethodTile(
                        key: const Key('fingerprint-method-option'),
                        icon: Icons.fingerprint_rounded,
                        title: _isLoadingBiometrics
                            ? 'Checking fingerprint…'
                            : _biometricLabel,
                        subtitle: _isLoadingBiometrics
                            ? 'Checking this phone'
                            : _canUseBiometrics
                            ? 'Use the fingerprint saved on this phone'
                            : 'Fingerprint is not available on this phone',
                        onTap: _canUseBiometrics && !_isAuthenticating
                            ? _authenticateWithBiometrics
                            : null,
                        isLoading: _isAuthenticating,
                      ),
                      const SizedBox(height: 12),
                      _buildUnlockMethodTile(
                        key: const Key('pattern-method-option'),
                        icon: Icons.pattern_rounded,
                        title: 'Pattern',
                        subtitle: 'Draw your saved 3×3 app pattern',
                        onTap: _isAuthenticating ? null : _selectPattern,
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('choose-unlock-method-button'),
                          onPressed: _showMethodChoices,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Choose another method'),
                        ),
                      ),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _message == null
                          ? const SizedBox(height: 38)
                          : Padding(
                              key: ValueKey(_message),
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _message!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ),
                    if (_showPattern)
                      SizedBox(
                        key: const Key('pattern-unlock-grid'),
                        width: 290,
                        height: 290,
                        child: IgnorePointer(
                          ignoring:
                              _isCheckingPattern ||
                              _lockoutSeconds > 0 ||
                              _isAuthenticating,
                          child: PatternLock(
                            selectedColor: AppColors.primary,
                            notSelectedColor: AppColors.cardBorder,
                            pointRadius: 11,
                            fillPoints: true,
                            relativePadding: 0.7,
                            onInputComplete: _checkPattern,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockMethodTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    final enabled = onTap != null;

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: AppSurfaces.card(
            color: enabled ? AppColors.surface : AppColors.surfaceMuted,
            radius: 18,
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.primarySoft : AppColors.border,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: enabled ? AppColors.primary : AppColors.subtle,
                  size: 27,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? AppColors.ink : AppColors.muted,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _PoppingArrow(enabled: enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoppingArrow extends StatefulWidget {
  final bool enabled;

  const _PoppingArrow({required this.enabled});

  @override
  State<_PoppingArrow> createState() => _PoppingArrowState();
}

class _PoppingArrowState extends State<_PoppingArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _movement;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _movement = Tween<double>(
      begin: 0,
      end: 5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scale = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.enabled) {
      _controller.repeat(reverse: true, count: 4);
    }
  }

  @override
  void didUpdateWidget(covariant _PoppingArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _controller.repeat(reverse: true, count: 4);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_movement.value, 0),
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: widget.enabled ? AppColors.primarySoft : AppColors.border,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_forward_rounded,
          size: 20,
          color: widget.enabled ? AppColors.primary : AppColors.subtle,
        ),
      ),
    );
  }
}
