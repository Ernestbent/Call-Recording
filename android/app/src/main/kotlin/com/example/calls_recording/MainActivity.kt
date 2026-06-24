package com.example.calls_recording

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "call_recorder_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                if (call.method == "startService") {

                    val intent = Intent(this, CallRecorderService::class.java)
                    startForegroundService(intent)

                    result.success("Service Started")

                } else if (call.method == "stopService") {

                    val intent = Intent(this, CallRecorderService::class.java)
                    stopService(intent)

                    result.success("Service Stopped")

                } else {
                    result.notImplemented()
                }
            }
    }
}