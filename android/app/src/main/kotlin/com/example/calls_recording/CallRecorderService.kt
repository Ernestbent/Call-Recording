package com.example.calls_recording

import android.app.*
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import java.io.File

class CallRecorderService : Service() {

    private var recorder: MediaRecorder? = null
    private var isRecording = false
    private var outputPath: String = ""

    private var telephonyManager: TelephonyManager? = null
    private var callCallback: TelephonyCallback? = null

    override fun onCreate() {
        super.onCreate()

        startForegroundService()
        startCallListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    private fun startForegroundService() {

        val channelId = "call_recorder_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Call Recorder",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Call Recorder Active")
            .setContentText("Listening for calls...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()

        startForeground(1, notification)
    }

    private fun startCallListener() {

        telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {

            callCallback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {

                override fun onCallStateChanged(state: Int) {

                    when (state) {
                        TelephonyManager.CALL_STATE_OFFHOOK -> startRecording()
                        TelephonyManager.CALL_STATE_IDLE -> stopRecording()
                    }
                }
            }

            telephonyManager?.registerTelephonyCallback(
                mainExecutor,
                callCallback as TelephonyCallback
            )
        }
    }

    private fun startRecording() {
        if (isRecording) return

        val file = File(getExternalFilesDir(null), "call_${System.currentTimeMillis()}.m4a")
        outputPath = file.absolutePath

        recorder = MediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setOutputFile(outputPath)

            prepare()
            start()
        }

        isRecording = true
    }

    private fun stopRecording() {
        if (!isRecording) return

        recorder?.apply {
            stop()
            release()
        }

        recorder = null
        isRecording = false
    }

    override fun onDestroy() {
        super.onDestroy()

        telephonyManager = null
        callCallback = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}