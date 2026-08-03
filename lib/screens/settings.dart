import 'package:flutter/material.dart';
import 'package:calls_recording/models/erpnext_session.dart';
import 'package:calls_recording/services/agent_credential_service.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/services/secure_session_storage.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/screens/login_screen.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:calls_recording/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final CustomerCallStore appState;
  final RecordingUploadSettings? uploadSettings;
  final ErpNextAuthenticator? erpNextAuthenticator;
  final SessionStorage? sessionStorage;
  final AgentCredentialManager? credentialManager;

  const SettingsScreen({
    super.key,
    required this.appState,
    this.uploadSettings,
    this.erpNextAuthenticator,
    this.sessionStorage,
    this.credentialManager,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoRecordCalls = true;
  bool _isLoadingApiUrl = true;
  bool _isSavingApiUrl = false;
  bool _isLoadingProfile = true;
  bool _isLoggingOut = false;
  ErpNextSession? _session;

  final TextEditingController _apiUrlController = TextEditingController();
  late final RecordingUploadSettings _uploadSettings;
  late final ErpNextAuthenticator _erpNextAuthenticator;
  late final SessionStorage _sessionStorage;
  late final AgentCredentialManager _credentialManager;

  @override
  void initState() {
    super.initState();
    _uploadSettings = widget.uploadSettings ?? RecordingUploadSettings();
    _erpNextAuthenticator = widget.erpNextAuthenticator ?? ErpNextAuthService();
    _sessionStorage = widget.sessionStorage ?? SecureSessionStorage();
    _credentialManager =
        widget.credentialManager ?? SecureAgentCredentialManager();
    _loadApiUrl();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    ErpNextSession? session;
    try {
      session = await _sessionStorage.read();
    } catch (_) {
      // The active in-memory session still provides profile information.
    }
    session ??= widget.appState.activeErpNextSession;
    if (!mounted) return;

    setState(() {
      _session = session;
      _isLoadingProfile = false;
    });
  }

  Future<void> _showProfile() async {
    if (_isLoadingProfile) return;

    final session = _session ?? widget.appState.activeErpNextSession;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final displayName = session?.fullName.trim();
        final userId = session?.userId.trim();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Theme.of(
                    sheetContext,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    _profileInitials(displayName, userId),
                    style: TextStyle(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onPrimaryContainer,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  displayName == null || displayName.isEmpty
                      ? 'Signed-in user'
                      : displayName,
                  key: const Key('profile-full-name'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userId == null || userId.isEmpty ? 'ERPNext account' : userId,
                  key: const Key('profile-user-id'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('profile-logout-button'),
                    onPressed: _isLoggingOut
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            _confirmLogout();
                          },
                    icon: Image.asset(
                      'lib/images/switch.png',
                      width: 20,
                      height: 20,
                    ),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text(
          'You will need to enter your ERPNext username and password again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('confirm-logout-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: Image.asset('lib/images/switch.png', width: 20, height: 20),
            label: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });

    final session = _session ?? widget.appState.activeErpNextSession;
    if (session != null) {
      await _erpNextAuthenticator.logout(session);
    }

    try {
      await _sessionStorage.clear();
      await _credentialManager.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoggingOut = false;
      });
      _showApiMessage('Could not clear the saved login.', isError: true);
      return;
    }

    widget.appState.clearErpNextSession();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          appState: widget.appState,
          erpNextAuthenticator: _erpNextAuthenticator,
          sessionStorage: _sessionStorage,
          credentialManager: _credentialManager,
        ),
      ),
      (_) => false,
    );
  }

  static String _profileInitials(String? fullName, String? userId) {
    final source = fullName?.trim().isNotEmpty == true
        ? fullName!.trim()
        : userId?.trim() ?? '';
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
        actions: [
          IconButton(
            key: const Key('settings-profile-button'),
            tooltip: 'Profile and logout',
            onPressed: _isLoadingProfile || _isLoggingOut ? null : _showProfile,
            icon: _isLoadingProfile
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Image.asset('lib/images/switch.png', width: 28, height: 28),
          ),
          const SizedBox(width: 8),
        ],
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
              Text(
                'Personalise your workspace',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage recording behaviour and connections.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                      iconAsset: 'lib/images/rec-button.png',
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

                    _buildSectionHeader('Appearance'),
                    _buildSwitchTile(
                      iconAsset: 'lib/images/night-mode.png',
                      title: 'Dark Mode',
                      subtitle: 'Switch between light and dark theme',
                      value: widget.appState.isDarkMode,
                      switchKey: const Key('settings-dark-mode-switch'),
                      onChanged: (value) async {
                        try {
                          await widget.appState.setDarkMode(value);
                        } catch (_) {
                          _showApiMessage(
                            'Could not save the theme preference.',
                            isError: true,
                          );
                        }
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: AppSurfaces.card(
        color: colorScheme.surfaceContainerHighest,
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
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
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
    required String iconAsset,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? switchKey,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: AppSurfaces.card(
        color: colorScheme.surfaceContainerHighest,
        radius: 14,
        elevated: false,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Image.asset(
                iconAsset,
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
