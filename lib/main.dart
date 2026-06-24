import 'package:calls_recording/controllers/call_controller.dart';
import 'package:flutter/material.dart';
import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/call_manager.dart';
import 'package:calls_recording/services/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create controller
  final controller = CallController(
    callManager: CallManager(),
    sessionManager: SessionManager(),
  );

  // Initialize (this will print debug logs)
  await controller.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}