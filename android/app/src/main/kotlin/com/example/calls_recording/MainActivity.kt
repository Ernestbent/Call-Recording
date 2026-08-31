package com.example.calls_recording

import android.content.ContentUris
import android.content.Intent
import android.database.Cursor
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import kotlin.math.abs

class MainActivity : FlutterActivity() {

    private val CHANNEL = "call_recorder_service"
    private val TAG = "CALL_RECORD_LOOKUP"
    private val audioExtensions = setOf(
        "mp3",
        "m4a",
        "wav",
        "aac",
        "amr",
        "3gp",
        "ogg",
        "opus"
    )
    private lateinit var methodChannel: MethodChannel
    private var mediaPlayer: MediaPlayer? = null
    private var activeRecordingPath: String? = null
    private val recordingLookupExecutor = Executors.newSingleThreadExecutor()
    private val bracketedPhoneRegex = Regex("""\(([^)]*?\d[^)]*)\)""")
    private val fallbackPhoneRegex = Regex("""\d{7,15}""")
    private val filenameTimestampRegex = Regex("""(?<!\d)(\d{14})(?!\d)""")
    private val mediaStoreRelativePaths = listOf(
        "CallRecordings/",
        "Recordings/",
        "MIUI/sound_recorder/",
        "MIUI/sound_recorder/call_rec/",
        "Samsung/Call/",
        "Music/PhoneRecord/"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        methodChannel.setMethodCallHandler { call, result ->

                when (call.method) {
                    "startService" -> {
                        val intent = Intent(this, CallRecorderService::class.java)
                        startForegroundService(intent)

                        result.success("Service Started")
                    }
                    "stopService" -> {
                        val intent = Intent(this, CallRecorderService::class.java)
                        stopService(intent)

                        result.success("Service Stopped")
                    }
                    "consumeCompletedCalls" -> {
                        result.success(CallRecorderService.consumeCompletedCalls(this))
                    }
                    "findRecentCallRecording" -> {
                        val callEndTimeMillis = call.argument<Number>("callEndTimeMillis")?.toLong()
                        val windowSeconds = call.argument<Number>("windowSeconds")?.toLong() ?: 60L
                        val phoneNumber = call.argument<String>("phoneNumber")

                        if (callEndTimeMillis == null) {
                            result.error(
                                "MISSING_ARGUMENT",
                                "callEndTimeMillis is required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        recordingLookupExecutor.execute {
                            val recording = findRecentCallRecording(
                                phoneNumber = phoneNumber,
                                callEndTimeMillis = callEndTimeMillis,
                                windowSeconds = windowSeconds
                            )
                            runOnUiThread {
                                result.success(recording)
                            }
                        }
                    }
                    "findRecordingsForPhone" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")
                        if (phoneNumber.isNullOrBlank()) {
                            result.error("MISSING_ARGUMENT", "phoneNumber is required", null)
                            return@setMethodCallHandler
                        }

                        recordingLookupExecutor.execute {
                            val recordings = findRecordingsForPhone(phoneNumber)
                            runOnUiThread {
                                result.success(recordings.map { it.toResultMap() })
                            }
                        }
                    }
                    "getRecordingDurationMillis" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("MISSING_ARGUMENT", "filePath is required", null)
                            return@setMethodCallHandler
                        }

                        recordingLookupExecutor.execute {
                            val durationMillis = getRecordingDurationMillis(filePath)
                            runOnUiThread {
                                result.success(durationMillis)
                            }
                        }
                    }
                    "openDialer" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")

                        if (phoneNumber.isNullOrBlank()) {
                            result.error("MISSING_ARGUMENT", "phoneNumber is required", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(Intent.ACTION_DIAL).apply {
                            data = Uri.parse("tel:$phoneNumber")
                        }

                        startActivity(intent)
                        result.success(true)
                    }
                    "playRecording" -> {
                        val filePath = call.argument<String>("filePath")

                        if (filePath.isNullOrBlank()) {
                            result.error("MISSING_ARGUMENT", "filePath is required", null)
                            return@setMethodCallHandler
                        }

                        playRecording(filePath, result)
                    }
                    "pauseRecording" -> {
                        pauseRecording(result)
                    }
                    "resumeRecording" -> {
                        resumeRecording(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getRecordingDurationMillis(filePath: String): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(this, Uri.parse(filePath))
            } else {
                val file = File(filePath)
                if (!file.exists() || file.length() <= 0L) return null
                retriever.setDataSource(file.absolutePath)
            }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.takeIf { it > 0L }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read recording duration path=$filePath", error)
            null
        } finally {
            retriever.release()
        }
    }

    private fun findRecentCallRecording(
        phoneNumber: String?,
        callEndTimeMillis: Long,
        windowSeconds: Long
    ): Map<String, Any>? {
        val normalizedTarget = normalizePhoneNumber(phoneNumber)
        Log.d(
            TAG,
            "Lookup started. phone=$phoneNumber normalized=$normalizedTarget callEnd=$callEndTimeMillis"
        )
        val latestPhoneMatch = newerCandidate(
            findLatestPhoneMatch(
                directories = buildRecordingDirectories(),
                normalizedTarget = normalizedTarget
            )?.toRecordingCandidate(),
            findLatestPhoneMatchMediaStore(normalizedTarget)
        )
        val latestRecording = latestPhoneMatch ?: newerCandidate(
            findLatestRecordingFile(buildRecordingDirectories())?.toRecordingCandidate(),
            findLatestMediaStoreRecording()
        )
        Log.d(
            TAG,
            if (latestRecording == null) {
                "Lookup finished. No recording found."
            } else {
                "Lookup finished. Selected ${latestRecording.fileName} @ ${latestRecording.filePath}"
            }
        )
        return latestRecording?.toResultMap()
    }

    private fun findRecordingsForPhone(phoneNumber: String): List<RecordingCandidate> {
        val normalizedTarget = normalizePhoneNumber(phoneNumber) ?: return emptyList()
        val directories = buildRecordingDirectories()
        logDirectoryAccess(directories)
        val matches = LinkedHashMap<String, RecordingCandidate>()

        findAllPhoneMatchesInFiles(
            directories = directories,
            normalizedTarget = normalizedTarget
        ).forEach { candidate ->
            matches[candidate.filePath] = candidate
        }

        findAllPhoneMatchesMediaStore(normalizedTarget).forEach { candidate ->
            val directFileAlreadyFound = matches.values.any { directCandidate ->
                !directCandidate.filePath.startsWith("content://") &&
                    directCandidate.fileName == candidate.fileName &&
                    abs(
                        directCandidate.lastModifiedTime - candidate.lastModifiedTime
                    ) < 2_000L
            }
            if (!directFileAlreadyFound) {
                matches[candidate.filePath] = candidate
            }
        }

        Log.d(TAG, "Phone match results for $normalizedTarget count=${matches.size}")
        return matches.values
            .sortedByDescending { it.lastModifiedTime }
    }

    private fun findAllPhoneMatchesMediaStore(
        normalizedTarget: String
    ): List<RecordingCandidate> {
        return queryAllMediaStoreCandidates()
            .filter { candidate ->
                phoneNumbersMatch(
                    normalizedTarget,
                    candidate.phoneNumber
                        ?: extractPhoneNumberFromFileName(candidate.fileName)
                )
            }
    }

    private fun findAllPhoneMatchesInFiles(
        directories: List<String>,
        normalizedTarget: String
    ): List<RecordingCandidate> {
        val results = mutableListOf<RecordingCandidate>()

        directories
            .map(::File)
            .filter { it.exists() && it.isDirectory && it.canRead() }
            .forEach { directory ->
                directory
                    .walkTopDown()
                    .onFail { _, _ -> }
                    .filter(::isUsableRecordingFile)
                    .forEach { file ->
                        val extractedPhone = extractPhoneNumberFromPath(file.absolutePath)
                        if (!phoneNumbersMatch(normalizedTarget, extractedPhone)) {
                            return@forEach
                        }

                        results.add(file.toRecordingCandidate())
                    }
            }

        Log.d(TAG, "Direct file phone matches for $normalizedTarget count=${results.size}")
        return results
    }

    private fun findLatestMediaStoreRecording(): RecordingCandidate? {
        val candidate = queryAllMediaStoreCandidates().firstOrNull()
        Log.d(
            TAG,
            if (candidate == null) {
                "MediaStore latest recording search found nothing."
            } else {
                "MediaStore latest recording picked ${candidate.fileName}"
            }
        )
        return candidate
    }

    private fun findLatestPhoneMatchMediaStore(
        normalizedTarget: String?
    ): RecordingCandidate? {
        if (normalizedTarget == null) return null
        val candidate = queryAllMediaStoreCandidates().firstOrNull { recording ->
            phoneNumbersMatch(
                normalizedTarget,
                extractPhoneNumberFromFileName(recording.fileName)
            )
        }
        Log.d(
            TAG,
            if (candidate == null) {
                "MediaStore phone match found nothing for $normalizedTarget"
            } else {
                "MediaStore phone match picked ${candidate.fileName}"
            }
        )
        return candidate
    }

    private fun queryAllMediaStoreCandidates(): List<RecordingCandidate> {
        val merged = LinkedHashMap<String, RecordingCandidate>()

        queryAudioMediaStoreCandidates().forEach { candidate ->
            merged[candidate.filePath] = candidate
        }
        queryFilesMediaStoreCandidates().forEach { candidate ->
            val current = merged[candidate.filePath]
            if (current == null || candidate.lastModifiedTime > current.lastModifiedTime) {
                merged[candidate.filePath] = candidate
            }
        }

        val results = merged.values.sortedByDescending { it.lastModifiedTime }
        Log.d(TAG, "Merged MediaStore candidates count=${results.size}")
        return results
    }

    private fun queryAudioMediaStoreCandidates(): List<RecordingCandidate> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.RELATIVE_PATH,
            MediaStore.MediaColumns.SIZE
        )

        val selection = mediaStoreRelativePaths.joinToString(" OR ") {
            "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
        }
        val selectionArgs = mediaStoreRelativePaths.map { "$it%" }.toTypedArray()

        val cursor = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
        ) ?: return emptyList()

        cursor.use { mediaCursor ->
            return readMediaStoreCandidates(
                cursor = mediaCursor,
                contentBaseUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                idColumn = MediaStore.Audio.Media._ID,
                nameColumn = MediaStore.Audio.Media.DISPLAY_NAME,
                modifiedColumn = MediaStore.Audio.Media.DATE_MODIFIED,
                relativePathColumn = MediaStore.Audio.Media.RELATIVE_PATH,
                sizeColumn = MediaStore.MediaColumns.SIZE,
                sourceLabel = "Audio.Media"
            )
        }
    }

    private fun queryFilesMediaStoreCandidates(): List<RecordingCandidate> {
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.RELATIVE_PATH,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.SIZE
        )

        val selection = mediaStoreRelativePaths.joinToString(" OR ") {
            "${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE ?"
        }
        val selectionArgs = mediaStoreRelativePaths.map { "$it%" }.toTypedArray()
        val filesUri = MediaStore.Files.getContentUri("external")
        val cursor = contentResolver.query(
            filesUri,
            projection,
            selection,
            selectionArgs,
            "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
        ) ?: return emptyList()

        cursor.use { mediaCursor ->
            return readMediaStoreCandidates(
                cursor = mediaCursor,
                contentBaseUri = filesUri,
                idColumn = MediaStore.Files.FileColumns._ID,
                nameColumn = MediaStore.Files.FileColumns.DISPLAY_NAME,
                modifiedColumn = MediaStore.Files.FileColumns.DATE_MODIFIED,
                relativePathColumn = MediaStore.Files.FileColumns.RELATIVE_PATH,
                sizeColumn = MediaStore.Files.FileColumns.SIZE,
                sourceLabel = "Files"
            )
        }
    }

    private fun readMediaStoreCandidates(
        cursor: Cursor,
        contentBaseUri: Uri,
        idColumn: String,
        nameColumn: String,
        modifiedColumn: String,
        relativePathColumn: String,
        sizeColumn: String,
        sourceLabel: String
    ): List<RecordingCandidate> {
        val idIndex = cursor.getColumnIndexOrThrow(idColumn)
        val nameIndex = cursor.getColumnIndexOrThrow(nameColumn)
        val dateModifiedIndex = cursor.getColumnIndexOrThrow(modifiedColumn)
        val relativePathIndex = cursor.getColumnIndexOrThrow(relativePathColumn)
        val sizeIndex = cursor.getColumnIndexOrThrow(sizeColumn)
        val results = mutableListOf<RecordingCandidate>()

        while (cursor.moveToNext()) {
            val displayName = cursor.getString(nameIndex) ?: continue
            if (!isSupportedAudio(displayName)) {
                continue
            }
            if (cursor.getLong(sizeIndex) <= 0L) continue

            val id = cursor.getLong(idIndex)
            val lastModified = cursor.getLong(dateModifiedIndex) * 1000L
            val relativePath = cursor.getString(relativePathIndex).orEmpty()
            val contentUri = ContentUris.withAppendedId(contentBaseUri, id)
            results.add(
                RecordingCandidate(
                    filePath = contentUri.toString(),
                    fileName = displayName,
                    lastModifiedTime = lastModified,
                    phoneNumber = extractPhoneNumberFromPath("$relativePath$displayName")
                )
            )
        }

        Log.d(TAG, "$sourceLabel candidates count=${results.size}")
        return results
    }

    private fun findLatestPhoneMatch(
        directories: List<String>,
        normalizedTarget: String?
    ): File? {
        if (normalizedTarget == null) return null

        var bestMatch: File? = null
        var bestModifiedTime = Long.MIN_VALUE

        directories
            .map(::File)
            .filter { it.exists() && it.isDirectory && it.canRead() }
            .forEach { directory ->
                directory
                    .walkTopDown()
                    .onFail { _, _ -> }
                    .filter(::isUsableRecordingFile)
                    .forEach { file ->
                        val extractedPhone = extractPhoneNumberFromPath(file.absolutePath)
                        if (!phoneNumbersMatch(normalizedTarget, extractedPhone)) {
                            return@forEach
                        }

                        val lastModified = file.lastModified()
                        if (lastModified > bestModifiedTime) {
                            bestMatch = file
                            bestModifiedTime = lastModified
                        }
                    }
            }

        Log.d(
            TAG,
            if (bestMatch == null) {
                "File phone match found nothing for $normalizedTarget"
            } else {
                "File phone match picked ${bestMatch.absolutePath}"
            }
        )
        return bestMatch
    }

    private fun findLatestRecordingFile(
        directories: List<String>
    ): File? {
        var bestMatch: File? = null
        var bestModifiedTime = Long.MIN_VALUE

        directories
            .map(::File)
            .filter { it.exists() && it.isDirectory && it.canRead() }
            .forEach { directory ->
                directory
                    .walkTopDown()
                    .onFail { _, _ -> }
                    .filter(::isUsableRecordingFile)
                    .forEach { file ->
                        val lastModified = file.lastModified()
                        if (lastModified > bestModifiedTime) {
                            bestMatch = file
                            bestModifiedTime = lastModified
                        }
                    }
            }

        Log.d(
            TAG,
            if (bestMatch == null) {
                "Latest file fallback found nothing."
            } else {
                "Latest file fallback picked ${bestMatch.absolutePath}"
            }
        )
        return bestMatch
    }

    private fun findBestMediaStoreRecordingMatch(
        normalizedTarget: String?,
        callEndTimeMillis: Long,
        windowMillis: Long
    ): RecordingCandidate? {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.RELATIVE_PATH,
            MediaStore.MediaColumns.SIZE
        )

        val selection = mediaStoreRelativePaths.joinToString(" OR ") {
            "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
        }
        val selectionArgs = mediaStoreRelativePaths
            .map { "$it%" }
            .toTypedArray()

        val cursor = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
        ) ?: return null

        cursor.use { mediaCursor ->
            return findBestRecordingMatchInCursor(
                cursor = mediaCursor,
                normalizedTarget = normalizedTarget,
                callEndTimeMillis = callEndTimeMillis,
                windowMillis = windowMillis
            )
        }
    }

    private fun findBestRecordingMatchInCursor(
        cursor: Cursor,
        normalizedTarget: String?,
        callEndTimeMillis: Long,
        windowMillis: Long
    ): RecordingCandidate? {
        val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
        val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
        val dateModifiedIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
        val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)

        var bestMatch: RecordingCandidate? = null
        var bestDelta = Long.MAX_VALUE
        var bestModifiedTime = Long.MIN_VALUE

        while (cursor.moveToNext()) {
            val displayName = cursor.getString(nameIndex) ?: continue
            if (!isSupportedAudio(displayName)) {
                continue
            }
            if (cursor.getLong(sizeIndex) <= 0L) continue

            val extractedPhone = extractPhoneNumberFromFileName(displayName)
            val hasPhoneMatch = normalizedTarget == null ||
                phoneNumbersMatch(normalizedTarget, extractedPhone)

            if (!hasPhoneMatch) {
                continue
            }

            val id = cursor.getLong(idIndex)
            val lastModified = cursor.getLong(dateModifiedIndex) * 1000L
            val candidateTimestamps = buildList {
                add(lastModified)
                extractTimestampFromFileName(displayName)?.let { add(it) }
            }
            val bestFileDelta = candidateTimestamps.minOf {
                abs(it - callEndTimeMillis)
            }
            val isInsideWindow = bestFileDelta <= windowMillis
            val isBetterMatch = bestFileDelta < bestDelta ||
                (bestFileDelta == bestDelta && lastModified > bestModifiedTime)

            if (!isInsideWindow || !isBetterMatch) {
                continue
            }

            val contentUri = ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                id
            )
            bestMatch = RecordingCandidate(
                filePath = contentUri.toString(),
                fileName = displayName,
                lastModifiedTime = lastModified
            )
            bestDelta = bestFileDelta
            bestModifiedTime = lastModified
        }

        return bestMatch
    }

    private fun findBestRecordingMatch(
        directories: List<String>,
        normalizedTarget: String?,
        callEndTimeMillis: Long,
        windowMillis: Long
    ): File? {
        var bestMatch: File? = null
        var bestDelta = Long.MAX_VALUE
        var bestModifiedTime = Long.MIN_VALUE

        directories
            .map(::File)
            .filter { it.exists() && it.isDirectory && it.canRead() }
            .forEach { directory ->
                directory
                    .walkTopDown()
                    .onFail { _, _ -> }
                    .filter(::isUsableRecordingFile)
                    .forEach { file ->
                        val lastModified = file.lastModified()
                        val extractedPhone = extractPhoneNumberFromFileName(file.name)
                        val hasPhoneMatch = normalizedTarget == null ||
                            phoneNumbersMatch(normalizedTarget, extractedPhone)

                        if (!hasPhoneMatch) {
                            return@forEach
                        }

                        val candidateTimestamps = buildList {
                            add(lastModified)
                            extractTimestampFromFileName(file.name)?.let { add(it) }
                        }
                        val bestFileDelta = candidateTimestamps.minOf {
                            abs(it - callEndTimeMillis)
                        }
                        val isInsideWindow = bestFileDelta <= windowMillis
                        val isBetterMatch = bestFileDelta < bestDelta ||
                            (bestFileDelta == bestDelta && lastModified > bestModifiedTime)

                        if (isInsideWindow && isBetterMatch) {
                            bestMatch = file
                            bestDelta = bestFileDelta
                            bestModifiedTime = lastModified
                        }
                    }
            }

        return bestMatch
    }

    private fun isSupportedAudio(file: File): Boolean {
        val extension = file.extension.lowercase()
        return extension in audioExtensions
    }

    private fun isUsableRecordingFile(file: File): Boolean {
        return file.isFile && file.length() > 0L && isSupportedAudio(file)
    }

    private fun isSupportedAudio(fileName: String): Boolean {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return extension in audioExtensions
    }

    private fun extractPhoneNumberFromFileName(fileName: String): String? {
        val bracketMatch = bracketedPhoneRegex.find(fileName)
            ?.groupValues
            ?.getOrNull(1)

        if (!bracketMatch.isNullOrBlank()) {
            return normalizePhoneNumber(bracketMatch)
        }

        val timestampMatch = filenameTimestampRegex.find(fileName)?.groupValues?.getOrNull(1)
        val fallbackMatch = fallbackPhoneRegex
            .findAll(fileName)
            .map { it.value }
            .filter { it != timestampMatch }
            .filter { isPlausiblePhoneDigits(it) }
            .maxByOrNull { it.length }

        return normalizePhoneNumber(fallbackMatch)
    }

    private fun extractPhoneNumberFromPath(path: String): String? {
        return path
            .split('/', '\\')
            .asReversed()
            .firstNotNullOfOrNull(::extractPhoneNumberFromFileName)
    }

    private fun isPlausiblePhoneDigits(value: String): Boolean {
        return when {
            value.startsWith("00") -> value.length in 11..15
            value.startsWith("0") -> value.length in 10..12
            else -> value.length in 9..12
        }
    }

    private fun extractTimestampFromFileName(fileName: String): Long? {
        val rawTimestamp = filenameTimestampRegex.find(fileName)?.groupValues?.getOrNull(1)
            ?: return null

        return try {
            val formatter = SimpleDateFormat("yyyyMMddHHmmss", Locale.US).apply {
                isLenient = false
                timeZone = TimeZone.getDefault()
            }
            formatter.parse(rawTimestamp)?.time
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizePhoneNumber(phoneNumber: String?): String? {
        if (phoneNumber.isNullOrBlank()) return null

        val digitsOnly = phoneNumber.filter { it.isDigit() }
        if (digitsOnly.isBlank()) return null

        val withoutInternationalPrefix = digitsOnly.removePrefix("00")
        return when {
            withoutInternationalPrefix.length > 9 ->
                withoutInternationalPrefix.takeLast(9)
            else -> withoutInternationalPrefix
        }
    }

    private fun phoneNumbersMatch(target: String?, candidate: String?): Boolean {
        if (target == null || candidate == null) return false
        return target == candidate || target.endsWith(candidate) || candidate.endsWith(target)
    }

    private fun newerCandidate(
        first: RecordingCandidate?,
        second: RecordingCandidate?
    ): RecordingCandidate? {
        return when {
            first == null -> second
            second == null -> first
            first.lastModifiedTime >= second.lastModifiedTime -> first
            else -> second
        }
    }

    private fun buildRecordingDirectories(): List<String> {
        val directories = mutableListOf(
            "/storage/emulated/0/CallRecordings/",
            "/storage/emulated/0/Recordings/",
            "/storage/emulated/0/MIUI/sound_recorder/",
            "/storage/emulated/0/MIUI/sound_recorder/call_rec/",
            "/storage/emulated/0/Samsung/Call/",
            "/storage/emulated/0/Music/PhoneRecord/"
        )

        getExternalFilesDir(null)?.absolutePath?.let { directories.add(it) }
        getExternalFilesDir(null)?.let { externalRoot ->
            directories.add(File(externalRoot, "recordings").absolutePath)
        }

        return directories.distinct()
    }

    private fun logDirectoryAccess(directories: List<String>) {
        directories.forEach { path ->
            val directory = File(path)
            Log.d(
                TAG,
                "Directory check path=$path exists=${directory.exists()} isDirectory=${directory.isDirectory} canRead=${directory.canRead()}"
            )
        }
    }

    private fun playRecording(filePath: String, result: MethodChannel.Result) {
        releaseMediaPlayer()

        val player = MediaPlayer()
        mediaPlayer = player
        activeRecordingPath = filePath
        var resultDelivered = false

        fun reportError(message: String, details: String? = null) {
            Log.e(TAG, "$message path=$filePath details=${details ?: "none"}")
            if (!resultDelivered) {
                resultDelivered = true
                result.error("PLAYBACK_FAILED", message, details)
            }
        }

        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            player.setOnPreparedListener {
                if (mediaPlayer !== it) return@setOnPreparedListener

                it.start()
                Log.d(
                    TAG,
                    "Playback started path=$filePath durationMs=${it.duration}"
                )
                if (!resultDelivered) {
                    resultDelivered = true
                    result.success(true)
                }
            }
            player.setOnCompletionListener {
                Log.d(TAG, "Playback completed path=$filePath")
                methodChannel.invokeMethod(
                    "playbackCompleted",
                    mapOf("filePath" to filePath)
                )
                if (mediaPlayer === it) {
                    releaseMediaPlayer()
                } else {
                    it.release()
                }
            }
            player.setOnErrorListener { failedPlayer, what, extra ->
                reportError(
                    message = "Android could not play this recording.",
                    details = "MediaPlayer error what=$what extra=$extra"
                )
                if (resultDelivered) {
                    methodChannel.invokeMethod(
                        "playbackFailed",
                        mapOf("filePath" to filePath)
                    )
                }
                if (mediaPlayer === failedPlayer) {
                    releaseMediaPlayer()
                } else {
                    failedPlayer.release()
                }
                true
            }

            if (filePath.startsWith("content://")) {
                val descriptor = contentResolver.openAssetFileDescriptor(
                    Uri.parse(filePath),
                    "r"
                ) ?: throw IllegalArgumentException("Recording could not be opened")

                descriptor.use {
                    if (it.length >= 0) {
                        player.setDataSource(
                            it.fileDescriptor,
                            it.startOffset,
                            it.length
                        )
                    } else {
                        player.setDataSource(it.fileDescriptor)
                    }
                }
            } else {
                val recordingFile = File(filePath)
                if (!recordingFile.exists() || !recordingFile.isFile) {
                    throw IllegalArgumentException("Recording file does not exist")
                }
                if (!recordingFile.canRead() || recordingFile.length() == 0L) {
                    throw IllegalArgumentException("Recording file is not readable")
                }

                FileInputStream(recordingFile).use {
                    player.setDataSource(it.fd)
                }
            }

            player.prepareAsync()
        } catch (error: Exception) {
            reportError(
                message = "Unable to open this recording.",
                details = error.message
            )
            releaseMediaPlayer()
        }
    }

    private fun pauseRecording(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null) {
            result.error("NO_ACTIVE_PLAYBACK", "No recording is playing.", null)
            return
        }

        try {
            if (player.isPlaying) {
                player.pause()
            }
            Log.d(TAG, "Playback paused path=$activeRecordingPath")
            result.success(true)
        } catch (error: IllegalStateException) {
            result.error("PAUSE_FAILED", "Unable to pause this recording.", error.message)
        }
    }

    private fun resumeRecording(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null) {
            result.error("NO_ACTIVE_PLAYBACK", "No recording is paused.", null)
            return
        }

        try {
            player.start()
            Log.d(TAG, "Playback resumed path=$activeRecordingPath")
            result.success(true)
        } catch (error: IllegalStateException) {
            result.error("RESUME_FAILED", "Unable to resume this recording.", error.message)
        }
    }

    private fun releaseMediaPlayer() {
        mediaPlayer?.let { player ->
            try {
                if (player.isPlaying) {
                    player.stop()
                }
            } catch (_: IllegalStateException) {
                // The player may still be preparing.
            }
            player.reset()
            player.release()
        }
        mediaPlayer = null
        activeRecordingPath = null
    }

    override fun onDestroy() {
        recordingLookupExecutor.shutdown()
        releaseMediaPlayer()
        super.onDestroy()
    }

    private data class RecordingCandidate(
        val filePath: String,
        val fileName: String,
        val lastModifiedTime: Long,
        val phoneNumber: String? = null
    ) {
        fun toResultMap(): Map<String, Any> {
            return mapOf(
                "filePath" to filePath,
                "fileName" to fileName,
                "lastModifiedTime" to lastModifiedTime
            )
        }
    }

    private fun File.toRecordingCandidate(): RecordingCandidate {
        return RecordingCandidate(
            filePath = absolutePath,
            fileName = name,
            lastModifiedTime = lastModified(),
            phoneNumber = extractPhoneNumberFromPath(absolutePath)
        )
    }
}
