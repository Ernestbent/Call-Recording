import 'package:flutter/services.dart';

class ServiceStarter {
  static const platform = MethodChannel('call_recorder_service');

  static Future<void> startService() async {
    try {
      await platform.invokeMethod('startService');
    } catch (e) {
      print("Failed to start service: $e");
    }
  }
}