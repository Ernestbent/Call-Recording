import 'package:calls_recording/controllers/call_controller.dart';
import 'package:flutter/material.dart';
import 'package:calls_recording/screens/splash_screen.dart';
import 'package:calls_recording/services/call_manager.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/session_manager.dart';
import 'package:calls_recording/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final customerCallStore = CustomerCallStore();
  await customerCallStore.hydrate();

  final controller = CallController(
    callManager: CallManager(),
    sessionManager: SessionManager(),
    customerCallStore: customerCallStore,
  );

  await controller.init();

  runApp(MyApp(appState: customerCallStore));
}

class MyApp extends StatelessWidget {
  final CustomerCallStore appState;

  const MyApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Recorder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: SplashScreen(appState: appState),
    );
  }
}
