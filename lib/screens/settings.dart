import 'package:flutter/material.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/widgets/custom_bottom_nav.dart';

class SettingsScreen extends StatefulWidget {
  final CustomerCallStore appState;

  const SettingsScreen({super.key, required this.appState});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoRecordCalls = true;
  bool _darkMode = false;
  String _apiUrl = '';

  final TextEditingController _apiUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = _apiUrl;
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
        centerTitle: true,
        toolbarHeight: 80,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Open Sans',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Color(0xFF554B42),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: Color(0xFFD9D9D9), thickness: 1, height: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF554B42)),
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Settings title
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF554B42),
              ),
            ),
            const SizedBox(height: 20),

            // Settings list
            Expanded(
              child: ListView(
                children: [
                  // API URL Section
                  _buildSectionHeader('API Configuration'),
                  _buildApiUrlField(),
                  const SizedBox(height: 16),

                  // Call Settings Section
                  _buildSectionHeader('Call Settings'),
                  _buildSwitchTile(
                    title: 'Auto-Record Calls',
                    subtitle: 'Automatically record all incoming calls',
                    value: _autoRecordCalls,
                    onChanged: (value) {
                      setState(() {
                        _autoRecordCalls = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Appearance Settings
                  _buildSectionHeader('Appearance'),
                  _buildSwitchTile(
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
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 3,
        appState: widget.appState,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildApiUrlField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: Color(0xFFE17C0F), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                hintText: 'https://127.0.0.1:8002/api/upload/',
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF554B42)),
              onChanged: (value) {
                setState(() {
                  _apiUrl = value;
                });
              },
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.check_circle,
              color: Color(0xFFE17C0F),
              size: 20,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('API URL saved successfully!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF554B42),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFE17C0F),
            activeTrackColor: const Color(0xFFE17C0F).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
