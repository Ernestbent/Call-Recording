import 'package:flutter/material.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/recording_upload_service.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';
import 'package:calls_recording/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final CustomerCallStore appState;
  final RecordingUploadSettings? uploadSettings;

  const SettingsScreen({
    super.key,
    required this.appState,
    this.uploadSettings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoRecordCalls = true;
  bool _darkMode = false;
  bool _isLoadingApiUrl = true;
  bool _isSavingApiUrl = false;

  final TextEditingController _apiUrlController = TextEditingController();
  late final RecordingUploadSettings _uploadSettings;

  @override
  void initState() {
    super.initState();
    _uploadSettings = widget.uploadSettings ?? RecordingUploadSettings();
    _loadApiUrl();
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
    required Function(bool) onChanged,
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
}
