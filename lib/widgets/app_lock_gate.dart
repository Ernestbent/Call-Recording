import 'package:calls_recording/screens/app_lock_screen.dart';
import 'package:calls_recording/screens/pattern_setup_screen.dart';
import 'package:calls_recording/screens/splash_screen.dart';
import 'package:calls_recording/services/app_lock_service.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';

class AppLockGate extends StatefulWidget {
  final CustomerCallStore appState;
  final AppLockService? appLockService;

  const AppLockGate({super.key, required this.appState, this.appLockService});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _appNavigatorKey =
      GlobalKey<NavigatorState>();

  late final AppLockService _appLockService;
  AppLockConfiguration _configuration = AppLockConfiguration.disabled;
  bool _isLoading = true;
  bool _isFinishingSetup = false;
  bool _isLocked = false;
  bool _hasStartedApp = false;
  bool _biometricAuthenticationInProgress = false;
  bool _wasBackgrounded = false;
  int _lockScreenVersion = 0;

  @override
  void initState() {
    super.initState();
    _appLockService = widget.appLockService ?? AppLockService();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialConfiguration();
  }

  Future<void> _loadInitialConfiguration() async {
    final configuration = await _appLockService.readConfiguration();
    if (!mounted) return;

    setState(() {
      _configuration = configuration;
      _isLocked = configuration.patternConfigured;
      _hasStartedApp = false;
      _isLoading = false;
    });
  }

  Future<void> _finishRequiredSetup() async {
    if (_isFinishingSetup) return;
    setState(() {
      _isFinishingSetup = true;
    });

    final biometrics = await _appLockService.availableBiometrics();
    if (biometrics.isNotEmpty) {
      await _appLockService.setBiometricsEnabled(true);
    }
    final configuration = await _appLockService.readConfiguration();
    if (!mounted) return;

    setState(() {
      _configuration = configuration;
      _isFinishingSetup = false;
      _isLocked = false;
      _hasStartedApp = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_biometricAuthenticationInProgress) {
      _wasBackgrounded = true;
      if (_configuration.enabled && _hasStartedApp && !_isLocked) {
        setState(() {
          _isLocked = true;
          _lockScreenVersion++;
        });
      }
    }

    if (state == AppLifecycleState.resumed) {
      _refreshConfiguration();
    }
  }

  Future<void> _refreshConfiguration() async {
    final configuration = await _appLockService.readConfiguration();
    if (!mounted) return;

    setState(() {
      _configuration = configuration;
      if (!configuration.enabled) {
        _isLocked = false;
        _hasStartedApp = true;
      } else if (_wasBackgrounded && _hasStartedApp && !_isLocked) {
        _isLocked = true;
        _lockScreenVersion++;
      }
      _wasBackgrounded = false;
    });
  }

  void _unlock() {
    setState(() {
      _isLocked = false;
      _hasStartedApp = true;
    });
  }

  Widget _buildAppNavigator() {
    return Navigator(
      key: _appNavigatorKey,
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(
          builder: (_) => SplashScreen(appState: widget.appState),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ColoredBox(
        color: AppColors.darkSurface,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (!_configuration.patternConfigured) {
      return Stack(
        fit: StackFit.expand,
        children: [
          PatternSetupScreen(
            appLockService: _appLockService,
            canCancel: false,
            onPatternSaved: _finishRequiredSetup,
          ),
          if (_isFinishingSetup)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      );
    }

    if (!_hasStartedApp) {
      return AppLockScreen(
        key: ValueKey(_lockScreenVersion),
        appLockService: _appLockService,
        biometricsEnabled: _configuration.biometricsEnabled,
        onUnlocked: _unlock,
        onBiometricAuthenticationChanged: (inProgress) {
          _biometricAuthenticationInProgress = inProgress;
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildAppNavigator(),
        if (_isLocked)
          AppLockScreen(
            key: ValueKey(_lockScreenVersion),
            appLockService: _appLockService,
            biometricsEnabled: _configuration.biometricsEnabled,
            onUnlocked: _unlock,
            onBiometricAuthenticationChanged: (inProgress) {
              _biometricAuthenticationInProgress = inProgress;
            },
          ),
      ],
    );
  }
}
