import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/app_lock_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/screens/pattern_setup_screen.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:calls_recording/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final CustomerCallStore appState;
  final RecordingUploadSettings? uploadSettings;
  final AppLockService? appLockService;

  const SettingsScreen({
    super.key,
    required this.appState,
    this.uploadSettings,
    this.appLockService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoRecordCalls = true;
  bool _darkMode = false;
  bool _isLoadingApiUrl = true;
  bool _isSavingApiUrl = false;
  bool _isLoadingSecurity = true;
  bool _isUpdatingSecurity = false;
  bool _hasEnrolledBiometrics = false;
  String _biometricName = 'Biometric unlock';
  AppLockConfiguration _lockConfiguration = AppLockConfiguration.disabled;

  final TextEditingController _apiUrlController = TextEditingController();
  late final RecordingUploadSettings _uploadSettings;
  late final AppLockService _appLockService;

  @override
  void initState() {
    super.initState();
    _uploadSettings = widget.uploadSettings ?? RecordingUploadSettings();
    _appLockService = widget.appLockService ?? AppLockService();
    _loadApiUrl();
    _loadSecurity();
  }

  Future<void> _loadSecurity() async {
    final results = await Future.wait([
      _appLockService.readConfiguration(),
      _appLockService.availableBiometrics(),
    ]);
    if (!mounted) return;

    final configuration = results[0] as AppLockConfiguration;
    final biometrics = results[1] as List<BiometricType>;
    setState(() {
      _lockConfiguration = configuration;
      _hasEnrolledBiometrics = biometrics.isNotEmpty;
      _biometricName = biometrics.contains(BiometricType.fingerprint)
          ? 'Fingerprint unlock'
          : biometrics.contains(BiometricType.face)
          ? 'Face unlock'
          : 'Biometric unlock';
      _isLoadingSecurity = false;
    });
  }

  Future<void> _setAppLockEnabled(bool enabled) async {
    if (_isUpdatingSecurity) return;

    if (enabled) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PatternSetupScreen(appLockService: _appLockService),
        ),
      );
      if (saved == true) {
        await _loadSecurity();
        _showApiMessage('App lock enabled.');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turn off app lock?'),
        content: const Text(
          'Your saved app pattern will be removed. You can create a new one '
          'later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isUpdatingSecurity = true;
    });
    try {
      await _appLockService.disable();
      await _loadSecurity();
      _showApiMessage('App lock turned off.');
    } catch (_) {
      _showApiMessage('Could not update app lock.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingSecurity = false;
        });
      }
    }
  }

  Future<void> _setBiometricsEnabled(bool enabled) async {
    if (_isUpdatingSecurity) return;

    setState(() {
      _isUpdatingSecurity = true;
    });
    try {
      if (enabled) {
        final authenticated = await _appLockService
            .authenticateWithBiometrics();
        if (!authenticated) {
          _showApiMessage(
            'Biometric verification was not completed.',
            isError: true,
          );
          return;
        }
      }
      await _appLockService.setBiometricsEnabled(enabled);
      await _loadSecurity();
      _showApiMessage(
        enabled ? 'Biometric unlock enabled.' : 'Biometric unlock disabled.',
      );
    } catch (_) {
      _showApiMessage('Could not update biometric unlock.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingSecurity = false;
        });
      }
    }
  }

  Future<void> _changePattern() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PatternSetupScreen(
          appLockService: _appLockService,
          isChangingPattern: true,
        ),
      ),
    );
    if (changed == true) {
      await _loadSecurity();
      _showApiMessage('App pattern changed.');
    }
  }

  Future<void> _loadApiUrl() async {
    final endpoint = await _uploadSettings.readEndpoint();
    if (!mounted) return;

    _apiUrlController.text = endpoint?.toString() ?? '';
    setState(() {
      _isLoadingApiUrl = false;
    });
  }

  Future<void> _saveApiUrl() async {
    final endpoint = RecordingUploadSettings.parseEndpoint(
      _apiUrlController.text,
    );
    if (endpoint == null) {
      _showApiMessage(
        'Enter a valid HTTP or HTTPS recording API URL.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSavingApiUrl = true;
    });

    try {
      await _uploadSettings.saveEndpoint(endpoint.toString());
      if (!mounted) return;
      _apiUrlController.text = endpoint.toString();
      _showApiMessage('Recording API URL saved.');
    } catch (_) {
      _showApiMessage('Could not save the recording API URL.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingApiUrl = false;
        });
      }
    }
  }

  void _showApiMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.warning : AppColors.success,
      ),
    );
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(appState: widget.appState),
              ),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personalise your workspace',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage recording behaviour and connections.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 26),

              Expanded(
                child: ListView(
                  children: [
                    _buildSectionHeader('API Configuration'),
                    _buildApiUrlField(),
                    const SizedBox(height: 24),

                    _buildSectionHeader('Call Settings'),
                    _buildSwitchTile(
                      icon: Icons.mic_none_rounded,
                      title: 'Auto-Record Calls',
                      subtitle: 'Automatically record all incoming calls',
                      value: _autoRecordCalls,
                      onChanged: (value) {
                        setState(() {
                          _autoRecordCalls = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    _buildSectionHeader('App Security'),
                    _buildSwitchTile(
                      icon: Icons.lock_outline_rounded,
                      title: 'App Lock',
                      subtitle: 'Require unlock before the splash screen',
                      value: _lockConfiguration.enabled,
                      onChanged: _isLoadingSecurity || _isUpdatingSecurity
                          ? null
                          : _setAppLockEnabled,
                    ),
                    const SizedBox(height: 10),
                    _buildSwitchTile(
                      icon: Icons.fingerprint_rounded,
                      title: _biometricName,
                      subtitle: _hasEnrolledBiometrics
                          ? 'Uses biometrics enrolled in this phone'
                          : 'No enrolled phone biometrics found',
                      value: _lockConfiguration.biometricsEnabled,
                      onChanged:
                          _isLoadingSecurity ||
                              _isUpdatingSecurity ||
                              !_lockConfiguration.enabled ||
                              !_hasEnrolledBiometrics
                          ? null
                          : _setBiometricsEnabled,
                    ),
                    if (_lockConfiguration.enabled) ...[
                      const SizedBox(height: 10),
                      _buildActionTile(
                        icon: Icons.pattern_rounded,
                        title: 'Change app pattern',
                        subtitle: 'Create a new 3×3 unlock pattern',
                        onTap: _isUpdatingSecurity ? null : _changePattern,
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
                      child: Text(
                        'Biometric access accepts any fingerprint or face '
                        'already enrolled by the phone. Use the app pattern '
                        'for another authorised user.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionHeader('Appearance'),
                    _buildSwitchTile(
                      icon: Icons.dark_mode_outlined,
                      title: 'Dark Mode',
                      subtitle: 'Switch between light and dark theme',
                      value: _darkMode,
                      onChanged: (value) {
                        setState(() {
                          _darkMode = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 3,
        appState: widget.appState,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionLabel(title),
    );
  }

  Widget _buildApiUrlField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: AppSurfaces.card(
        color: AppColors.surfaceMuted,
        radius: 14,
        elevated: false,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _apiUrlController,
              enabled: !_isLoadingApiUrl && !_isSavingApiUrl,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveApiUrl(),
              decoration: const InputDecoration(
                hintText: 'https://example.ngrok-free.dev/api/recordings',
                prefixIcon: Icon(Icons.link_rounded),
                border: InputBorder.none,
                filled: false,
              ),
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
          ),
          IconButton(
            icon: _isSavingApiUrl
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 19),
            color: Colors.white,
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _isLoadingApiUrl || _isSavingApiUrl ? null : _saveApiUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: AppSurfaces.card(
        color: AppColors.surfaceMuted,
        radius: 14,
        elevated: false,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.border,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppSurfaces.card(
            color: AppColors.surfaceMuted,
            radius: 14,
            elevated: false,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
            ],
          ),
        ),
      ),
    );
  }
}
