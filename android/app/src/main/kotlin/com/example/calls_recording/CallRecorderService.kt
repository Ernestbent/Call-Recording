package com.example.calls_recording

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class CallRecorderService : Service() {
    private var callStartedAtMillis: Long? = null
    private var telephonyManager: TelephonyManager? = null
    private var callCallback: TelephonyCallback? = null
    private var legacyCallListener: PhoneStateListener? = null
    private val worker = Executors.newSingleThreadScheduledExecutor()

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification("Listening for calls"))
        startCallListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (telephonyManager == null) startCallListener()
        return START_STICKY
    }

    private fun buildNotification(message: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Call monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps call recording detection active"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Calls Recorder active")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(message: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(message))
    }

    private fun startCallListener() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "READ_PHONE_STATE is not granted; call monitoring cannot start")
            return
        }

        val manager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager = manager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (callCallback != null) return
            callCallback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) = handleCallState(state)
            }
            manager.registerTelephonyCallback(mainExecutor, callCallback as TelephonyCallback)
        } else {
            if (legacyCallListener != null) return
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Deprecated("Deprecated in Android")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    handleCallState(state)
                }
            }
            legacyCallListener = listener
            @Suppress("DEPRECATION")
            manager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun handleCallState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK -> handleCallStarted()
            TelephonyManager.CALL_STATE_IDLE -> handleCallEnded()
        }
    }

    private fun handleCallStarted() {
        if (callStartedAtMillis != null) return
        callStartedAtMillis = System.currentTimeMillis()
        updateNotification("Call in progress")
    }

    private fun handleCallEnded() {
        val startedAt = callStartedAtMillis ?: return
        callStartedAtMillis = null
        val endedAt = System.currentTimeMillis()
        updateNotification("Processing completed call")
        resolveAndPersistCall(startedAt, endedAt, attempt = 1)
    }

    private fun resolveAndPersistCall(
        startedAt: Long,
        endedAt: Long,
        attempt: Int
    ) {
        worker.execute {
            val phoneNumber = latestCallNumber(startedAt, endedAt)
            if (phoneNumber == null && attempt < CALL_LOG_ATTEMPTS) {
                worker.schedule(
                    {
                        resolveAndPersistCall(
                            startedAt,
                            endedAt,
                            attempt + 1
                        )
                    },
                    CALL_LOG_RETRY_SECONDS,
                    java.util.concurrent.TimeUnit.SECONDS
                )
                return@execute
            }

            val normalizedPhone = normalizeUgandaPhoneNumber(phoneNumber)
            if (normalizedPhone != null) {
                persistFlutterCallTimestamps(normalizedPhone, startedAt, endedAt)
            }
            appendCompletedCall(
                phoneNumber = normalizedPhone,
                startedAt = startedAt,
                endedAt = endedAt,
                recording = null
            )
            updateNotification("Listening for calls")
        }
    }

    private fun latestCallNumber(startedAt: Long, endedAt: Long): String? {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val projection = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE)
        val selection = "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?"
        val selectionArgs = arrayOf(
            (startedAt - CALL_LOG_WINDOW_MILLIS).toString(),
            (endedAt + CALL_LOG_WINDOW_MILLIS).toString()
        )

        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${CallLog.Calls.DATE} DESC"
            )?.use { cursor ->
                val numberColumn = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                if (cursor.moveToFirst()) cursor.getString(numberColumn) else null
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to resolve the completed call from the call log", error)
            null
        }
    }

    private fun persistFlutterCallTimestamps(
        phoneNumber: String,
        startedAt: Long,
        endedAt: Long
    ) {
        getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putLong("flutter.customer_${phoneNumber}_last_call_started_at", startedAt)
            .putLong("flutter.customer_${phoneNumber}_last_call_ended_at", endedAt)
            .putString("flutter.last_resolved_phone_number", phoneNumber)
            .putLong("flutter.last_call_started_at", startedAt)
            .apply()
    }

    private fun appendCompletedCall(
        phoneNumber: String?,
        startedAt: Long,
        endedAt: Long,
        recording: java.io.File?
    ) {
        synchronized(COMPLETED_CALL_LOCK) {
            val preferences = getSharedPreferences(SERVICE_PREFERENCES, Context.MODE_PRIVATE)
            val calls = try {
                JSONArray(preferences.getString(COMPLETED_CALLS_KEY, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            val event = JSONObject()
                .put("id", "$startedAt-$endedAt")
                .put("startedAtMillis", startedAt)
                .put("endedAtMillis", endedAt)
            if (phoneNumber != null) event.put("phoneNumber", phoneNumber)
            if (recording != null && recording.exists()) {
                event.put("recordingPath", recording.absolutePath)
                event.put("recordingName", recording.name)
                event.put("recordingModifiedAtMillis", recording.lastModified())
            }
            calls.put(event)

            val trimmed = JSONArray()
            val start = (calls.length() - MAX_COMPLETED_CALLS).coerceAtLeast(0)
            for (index in start until calls.length()) trimmed.put(calls.get(index))
            preferences.edit().putString(COMPLETED_CALLS_KEY, trimmed.toString()).apply()
        }
    }

    override fun onDestroy() {
        val manager = telephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            callCallback?.let { manager?.unregisterTelephonyCallback(it) }
        } else {
            @Suppress("DEPRECATION")
            legacyCallListener?.let { manager?.listen(it, PhoneStateListener.LISTEN_NONE) }
        }
        callCallback = null
        legacyCallListener = null
        telephonyManager = null
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "CALL_FOREGROUND_SERVICE"
        private const val CHANNEL_ID = "call_recorder_channel"
        private const val NOTIFICATION_ID = 1001
        private const val SERVICE_PREFERENCES = "CallRecorderService"
        private const val COMPLETED_CALLS_KEY = "completed_calls"
        private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        private const val MAX_COMPLETED_CALLS = 50
        private const val CALL_LOG_ATTEMPTS = 5
        private const val CALL_LOG_RETRY_SECONDS = 2L
        private const val CALL_LOG_WINDOW_MILLIS = 120_000L
        private val COMPLETED_CALL_LOCK = Any()

        private fun normalizeUgandaPhoneNumber(raw: String?): String? {
            val digits = raw?.filter(Char::isDigit).orEmpty()
            if (digits.isEmpty()) return null
            return when {
                digits.startsWith("256") && digits.length == 12 -> "0${digits.substring(3)}"
                digits.length == 9 -> "0$digits"
                else -> digits
            }
        }

        fun consumeCompletedCalls(context: Context): List<Map<String, Any>> {
            synchronized(COMPLETED_CALL_LOCK) {
                val preferences = context.getSharedPreferences(
                    SERVICE_PREFERENCES,
                    Context.MODE_PRIVATE
                )
                val calls = try {
                    JSONArray(preferences.getString(COMPLETED_CALLS_KEY, "[]"))
                } catch (_: Exception) {
                    JSONArray()
                }
                val result = mutableListOf<Map<String, Any>>()
                for (index in 0 until calls.length()) {
                    val event = calls.optJSONObject(index) ?: continue
                    val item = mutableMapOf<String, Any>(
                        "id" to event.optString("id"),
                        "startedAtMillis" to event.optLong("startedAtMillis"),
                        "endedAtMillis" to event.optLong("endedAtMillis")
                    )
                    if (event.has("phoneNumber")) {
                        item["phoneNumber"] = event.optString("phoneNumber")
                    }
                    if (event.has("recordingPath")) {
                        item["recordingPath"] = event.optString("recordingPath")
                        item["recordingName"] = event.optString("recordingName")
                        item["recordingModifiedAtMillis"] =
                            event.optLong("recordingModifiedAtMillis")
                    }
                    result.add(item)
                }
                preferences.edit().remove(COMPLETED_CALLS_KEY).apply()
                return result
            }
        }
    }
}
