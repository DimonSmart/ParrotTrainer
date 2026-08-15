package vn.fighttechvn.stt_record

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.system.Os
import android.system.OsConstants
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.OutputStream
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 * Android implementation:
 * - Prefer a single mic source via AudioRecord.
 * - Stream PCM into SpeechRecognizer via audio-injection when supported.
 * - Write the same PCM to a WAV file.
 */
class SttRecordPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    
    private var actionReceiver: BroadcastReceiver? = null

    private var audioManager: AudioManager? = null
    private var audioFocusListener: AudioManager.OnAudioFocusChangeListener? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    @Volatile
    private var pausedByAudioFocus: Boolean = false

    @Volatile
    private var pausedByUser: Boolean = false

    private val lock = Any()

    @Volatile
    private var running: Boolean = false

    @Volatile
    private var pausedForInterruption: Boolean = false

    private val transcriptBuilder = StringBuilder()
    private var lastFinalSegment: String = ""
    private var lastPartialSegment: String = ""

    private var lastLocaleId: String = "vi-VN"
    private var lastPartialResults: Boolean = true

    private var lastSampleRate: Int = 16000
    private var lastChannelCount: Int = 1

    private var recognitionListener: RecognitionListener? = null

    private var continueListeningRunnable: Runnable? = null

    private var continueListeningAttempt: Int = 0
    private var silenceErrorStreak: Int = 0

    private var resumeAttempt: Int = 0
    private var resumeRunnable: Runnable? = null

    private val maxResumeAttemptsBeforeFallback: Int = 5

    // Proactively close the current recognition segment well before any internal
    // service limit (commonly ~2 minutes on Android SpeechRecognizer). Forcing
    // onResults via stopListening() locks the running partial into the
    // accumulated transcript so it is not lost when the service silently resets.
    private val maxSegmentDurationMs: Long = 25_000L
    private var segmentRotateRunnable: Runnable? = null

    private var pendingPermissionResult: Result? = null
    private val permissionRequestCode: Int = 48421

    private var speechRecognizer: SpeechRecognizer? = null
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    private var wavWriter: WavWriter? = null
    private var audioPath: String? = null

    @Volatile
    private var lastAmplitude: Double = 0.0

    private var pipeReadPfd: ParcelFileDescriptor? = null
    private var pipeWritePfd: ParcelFileDescriptor? = null
    private var pipeWriteStream: OutputStream? = null
    private var injectStreamId: String? = null

    private enum class Mode {
        INJECTION,
        LISTENER_BUFFER
    }

    private var mode: Mode? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        audioManager = flutterPluginBinding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "stt_record/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "stt_record/events")
        eventChannel.setStreamHandler(this)

        actionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val dummyResult = object : Result {
                    override fun success(result: Any?) {}
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                    override fun notImplemented() {}
                }
                when (intent?.action) {
                    SttRecordForegroundService.BROADCAST_PAUSE -> pause(dummyResult)
                    SttRecordForegroundService.BROADCAST_RESUME -> resume(dummyResult)
                    SttRecordForegroundService.BROADCAST_STOP -> stop(dummyResult)
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(SttRecordForegroundService.BROADCAST_PAUSE)
            addAction(SttRecordForegroundService.BROADCAST_RESUME)
            addAction(SttRecordForegroundService.BROADCAST_STOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext?.registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext?.registerReceiver(actionReceiver, filter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext?.unregisterReceiver(actionReceiver)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        abandonAudioFocus()
        audioManager = null
        applicationContext = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val snapshotText: String?
        val shouldEmitPaused: Boolean
        synchronized(lock) {
            eventSink = events
            if (!running) {
                snapshotText = null
                shouldEmitPaused = false
            } else {
                val partial = lastPartialSegment.takeIf { it.isNotBlank() }
                snapshotText = buildFullTextLocked(partial)
                shouldEmitPaused = pausedForInterruption
            }
        }

        if (!snapshotText.isNullOrBlank()) {
            sendTranscript(snapshotText, isFinal = false)
        }
        if (shouldEmitPaused) {
            sendState("paused")
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            eventSink = null
        }
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != permissionRequestCode) return false

        var audioGranted = false
        for (i in permissions.indices) {
            if (permissions[i] == Manifest.permission.RECORD_AUDIO && grantResults[i] == PackageManager.PERMISSION_GRANTED) {
                audioGranted = true
            }
        }

        val pending = synchronized(lock) {
            val r = pendingPermissionResult
            pendingPermissionResult = null
            r
        }
        pending?.success(audioGranted)
        return true
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> {
                val onlyRecordAudio = call.argument<Boolean>("onlyRecordAudio") ?: false
                requestPermission(onlyRecordAudio, result)
            }
            "getLocales" -> getLocales(result)
            "start" -> {
                val localeId = call.argument<String>("localeId") ?: "vi-VN"
                val partialResults = call.argument<Boolean>("partialResults") ?: true
                val enableSystemNotification = call.argument<Boolean>("enableSystemNotification") ?: false
                val notificationTitle = call.argument<String>("systemNotificationTitle") ?: "Recording"
                val notificationBody = call.argument<String>("systemNotificationBody") ?: "Speech-to-text is running"
                val enableActionPause = call.argument<Boolean>("enableSystemNotificationActionPause") ?: true
                val enableActionStop = call.argument<Boolean>("enableSystemNotificationActionStop") ?: true
                start(localeId, partialResults, enableSystemNotification, notificationTitle, notificationBody, enableActionPause, enableActionStop, result)
            }
            "pause" -> pause(result)
            "resume" -> resume(result)
            "getAmplitude" -> result.success(lastAmplitude)
            "stop" -> stop(result)
            "cancel" -> cancel(result)
            else -> result.notImplemented()
        }
    }

    private fun getLocales(result: Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.error("no_context", "Plugin not attached to engine", null)
            return
        }

        // Best-effort: start with current device locale.
        val current = normalizeLocaleId(ctx.resources.configuration.locales[0].toLanguageTag())

        val hasPermission = ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && hasPermission) {
            if (SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)) {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
                val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                try {
                    recognizer.checkRecognitionSupport(recognizerIntent, java.util.concurrent.Executors.newSingleThreadExecutor(),
                        object : android.speech.RecognitionSupportCallback {
                            override fun onSupportResult(recognitionSupport: android.speech.RecognitionSupport) {
                                val supported = recognitionSupport.supportedOnDeviceLanguages
                                mainHandler.post {
                                    val out = mutableListOf<Map<String, String>>()
                                    val seen = LinkedHashSet<String>()
                                    fun addTag(raw: String?) {
                                        val id = normalizeLocaleId(raw) ?: return
                                        if (!seen.add(id)) return
                                        out.add(mapOf("localeId" to id, "name" to displayNameForTag(id)))
                                    }
                                    addTag(current)
                                    supported.forEach { addTag(it) }
                                    result.success(out)
                                    recognizer.destroy()
                                }
                            }
                            override fun onError(error: Int) {
                                mainHandler.post {
                                    fetchLocalesViaBroadcast(ctx, result, current)
                                    recognizer.destroy()
                                }
                            }
                        })
                    return
                } catch (e: Exception) {
                    // Fallback if checkRecognitionSupport fails
                }
            }
        }

        fetchLocalesViaBroadcast(ctx, result, current)
    }

    private fun fetchLocalesViaBroadcast(ctx: Context, result: Result, current: String?) {

        val detailsIntent = RecognizerIntent.getVoiceDetailsIntent(ctx)
            ?: Intent(RecognizerIntent.ACTION_GET_LANGUAGE_DETAILS).apply {
                // Fallback to the most common implementation on GMS devices.
                setPackage("com.google.android.googlequicksearchbox")
            }

        val receiver = LanguageDetailsReceiver(
            mainHandler = mainHandler,
            result = result,
            fallbackLocale = current,
        )

        // Timeout to avoid hanging the method call on devices without a handler.
        mainHandler.postDelayed({ receiver.timeout() }, 2_000L)

        ctx.sendOrderedBroadcast(
            detailsIntent,
            null,
            receiver,
            null,
            Activity.RESULT_OK,
            null,
            null,
        )
    }

    private fun normalizeLocaleId(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return trimmed.replace('_', '-')
    }

    private fun displayNameForTag(tag: String): String {
        return try {
            val locale = java.util.Locale.forLanguageTag(tag)
            val display = locale.getDisplayName(java.util.Locale.getDefault()).trim()
            if (display.isEmpty()) tag else display
        } catch (_: Exception) {
            tag
        }
    }

    private inner class LanguageDetailsReceiver(
        private val mainHandler: Handler,
        private val result: Result,
        private val fallbackLocale: String?,
    ) : BroadcastReceiver() {

        private val completed = AtomicBoolean(false)

        override fun onReceive(context: Context?, intent: Intent?) {
            val extras: Bundle? = try {
                getResultExtras(true)
            } catch (_: Exception) {
                null
            }

            val preferredRaw = extras?.getString(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE)
            val supported = mutableListOf<String>()

            extras?.getStringArrayList(RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES)?.let { supported.addAll(it) }
            extras?.getStringArray(RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES)?.let { supported.addAll(it) }

            val out = mutableListOf<Map<String, String>>()
            val seen = LinkedHashSet<String>()

            fun addTag(raw: String?) {
                val id = normalize(raw) ?: return
                if (!seen.add(id)) return
                out.add(mapOf("localeId" to id, "name" to displayNameForTag(id)))
            }

            addTag(preferredRaw)
            if (out.isEmpty()) {
                addTag(fallbackLocale)
            }
            for (item in supported) {
                addTag(item)
            }

            complete(out)
        }

        fun timeout() {
            val fallback = normalize(fallbackLocale)
            if (fallback.isNullOrEmpty()) {
                complete(emptyList())
                return
            }
            complete(listOf(mapOf("localeId" to fallback, "name" to displayNameForTag(fallback))))
        }

        private fun complete(locales: List<Map<String, String>>) {
            if (!completed.compareAndSet(false, true)) return
            // Ensure the method-channel reply is on the main thread.
            mainHandler.post { result.success(locales) }
        }

        private fun normalize(raw: String?): String? {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            return trimmed.replace('_', '-')
        }

    }

    private fun hasPermission(): Boolean {
        val ctx = applicationContext ?: return false
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(onlyRecordAudio: Boolean, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no_activity", "An Activity is required to request permissions", null)
            return
        }

        synchronized(lock) {
            if (pendingPermissionResult != null) {
                result.error("permission_in_progress", "Permission request already in progress", null)
                return
            }
            pendingPermissionResult = result
        }

        val permissionsToRequest = mutableListOf<String>()
        if (!hasPermission()) {
            permissionsToRequest.add(Manifest.permission.RECORD_AUDIO)
        }
        if (!onlyRecordAudio && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(currentActivity, "android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add("android.permission.POST_NOTIFICATIONS")
            }
        }

        if (permissionsToRequest.isEmpty()) {
            val pending = synchronized(lock) {
                val r = pendingPermissionResult
                pendingPermissionResult = null
                r
            }
            pending?.success(true)
            return
        }

        ActivityCompat.requestPermissions(
            currentActivity,
            permissionsToRequest.toTypedArray(),
            permissionRequestCode
        )
    }

    private fun start(localeId: String, partialResults: Boolean, enableSystemNotification: Boolean, notificationTitle: String, notificationBody: String, enableActionPause: Boolean, enableActionStop: Boolean, result: Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.error("no_context", "Plugin not attached to engine", null)
            return
        }

        synchronized(lock) {
            if (running) {
                result.error("already_running", "A session is already running", null)
                return
            }
            if (!hasPermission()) {
                result.error("permission_denied", "RECORD_AUDIO permission is required", null)
                return
            }
            if (!SpeechRecognizer.isRecognitionAvailable(ctx)) {
                result.error("stt_unavailable", "Speech recognition service is not available", null)
                return
            }

            running = true
            pausedForInterruption = false
            pausedByAudioFocus = false
            pausedByUser = false
            lastLocaleId = localeId
            lastPartialResults = partialResults

            lastAmplitude = 0.0

            continueListeningAttempt = 0
            silenceErrorStreak = 0

            clearTranscriptStateLocked()
        }

        cancelResume()
        cancelContinueListening()

        // Best-effort: request audio focus so we can reliably detect call interruptions.
        requestAudioFocus()

        // Keep process alive in background while recording.
        SttRecordForegroundService.start(ctx, enableSystemNotification, notificationTitle, notificationBody, enableActionPause, enableActionStop)

        // Create output file.
        val outFile = File(ctx.cacheDir, "stt_record_${System.currentTimeMillis()}.wav")
        audioPath = outFile.absolutePath

        // Default to 16k mono PCM16.
        val sampleRate = 16000
        val channelCount = 1

        synchronized(lock) {
            lastSampleRate = sampleRate
            lastChannelCount = channelCount
        }

        // Prepare WAV writer early.
        wavWriter = WavWriter(outFile, sampleRate = sampleRate, channelCount = channelCount, bitsPerSample = 16)

        try {
            startRecognizerAndCapture(
                ctx,
                localeId,
                partialResults,
                sampleRate,
                channelCount,
                allowListenerFallback = true,
            )
        } catch (e: Exception) {
            cleanupSession(deleteFile = true)
            result.error("start_failed", e.message, null)
            return
        }

        result.success(null)
    }

    private fun stop(result: Result) {
        val path = audioPath ?: ""
        Thread {
            cleanupSession(deleteFile = false)
            mainHandler.post {
                result.success(mapOf("audioPath" to path))
            }
        }.start()
    }

    private fun cancel(result: Result) {
        Thread {
            cleanupSession(deleteFile = true)
            mainHandler.post { result.success(null) }
        }.start()
    }

    private fun cancelResume() {
        val r = synchronized(lock) {
            val existing = resumeRunnable
            resumeRunnable = null
            resumeAttempt = 0
            existing
        }
        if (r != null) {
            mainHandler.removeCallbacks(r)
        }
    }
    private fun cancelContinueListening() {
        val r = synchronized(lock) {
            val existing = continueListeningRunnable
            continueListeningRunnable = null
            existing
        }
        if (r != null) {
            mainHandler.removeCallbacks(r)
        }
    }

    private fun cancelSegmentRotate() {
        val r = synchronized(lock) {
            val existing = segmentRotateRunnable
            segmentRotateRunnable = null
            existing
        }
        if (r != null) {
            mainHandler.removeCallbacks(r)
        }
    }

    private fun armSegmentRotate() {
        val runnable = Runnable {
            synchronized(lock) {
                if (!running) return@Runnable
                if (pausedForInterruption) return@Runnable
                if (pausedByUser) return@Runnable
                segmentRotateRunnable = null
            }
            // Ask the recognizer to finalize the current hypothesis. This will
            // trigger onResults, which appends to transcriptBuilder and then
            // schedules continueListening for the next segment.
            runCatching { speechRecognizer?.stopListening() }
        }

        synchronized(lock) {
            if (!running) return
            if (pausedForInterruption) return
            if (pausedByUser) return
            segmentRotateRunnable?.let { mainHandler.removeCallbacks(it) }
            segmentRotateRunnable = runnable
        }
        mainHandler.postDelayed(runnable, maxSegmentDurationMs)
    }

    private fun resetSpeechRecognizerForContinueListening() {
        val sr: SpeechRecognizer? = synchronized(lock) {
            val existing = speechRecognizer
            speechRecognizer = null
            existing
        }
        if (sr == null) return

        val runnable = Runnable {
            runCatching { sr.stopListening() }
            runCatching { sr.cancel() }
            runCatching { sr.destroy() }
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run()
        } else {
            mainHandler.post(runnable)
        }
    }

    private fun computeBackoffMs(attempt: Int, baseMs: Long = 250L, maxMs: Long = 2_000L): Long {
        if (attempt <= 0) return baseMs
        return minOf(maxMs, baseMs * attempt.toLong())
    }

    private fun scheduleContinueListening(delayMs: Long = 200L) {
        val ctx = applicationContext ?: return

        val runnable = Runnable {
            continueListening(ctx)
        }

        synchronized(lock) {
            if (!running) return
            if (pausedForInterruption) return
            if (pausedByUser) return

            continueListeningRunnable?.let { mainHandler.removeCallbacks(it) }
            continueListeningRunnable = runnable
        }

        mainHandler.postDelayed(runnable, delayMs)
    }

    private fun continueListening(ctx: Context) {
        val localeId: String
        val partialResults: Boolean
        val sampleRate: Int
        val channelCount: Int
        val currentMode: Mode?

        synchronized(lock) {
            if (!running) return
            if (pausedForInterruption) return
            if (pausedByUser) return
            localeId = lastLocaleId
            partialResults = lastPartialResults
            sampleRate = lastSampleRate
            channelCount = lastChannelCount
            currentMode = mode
            continueListeningRunnable = null
        }

        val listener = recognitionListener ?: createRecognitionListener(sampleRate, channelCount).also {
            recognitionListener = it
        }

        val recognizer = speechRecognizer ?: SpeechRecognizer.createSpeechRecognizer(ctx).also { sr ->
            speechRecognizer = sr
            sr.setRecognitionListener(listener)
        }

        val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)

            // Best-effort: reduce premature end-of-speech on some devices/locales.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1200)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800)
        }

        if (currentMode == Mode.INJECTION) {
            // Ensure we provide a fresh one-shot injection source for each recognizer session.
            cleanupInjectionOnly()
            val injectionConfigured = runCatching {
                configureAudioInjectionIfPossible(ctx, recognizerIntent, sampleRate, channelCount)
            }.getOrDefault(false)

            if (!injectionConfigured) {
                // Injection unexpectedly unavailable; let the recognizer fall back to mic.
                // Note: this may conflict with AudioRecord on some devices, but is best-effort.
                mode = Mode.LISTENER_BUFFER
            } else {
                mode = Mode.INJECTION
            }
        }

        runCatching {
            recognizer.startListening(recognizerIntent)
        }.onSuccess {
            armSegmentRotate()
        }.onFailure {
            val attempt: Int
            synchronized(lock) {
                continueListeningAttempt += 1
                attempt = continueListeningAttempt
            }

            // Some devices/services reject rapid restarts with BUSY/CLIENT errors.
            // Avoid pausing the whole session; recreate the recognizer and retry with backoff.
            resetSpeechRecognizerForContinueListening()

            val delay = computeBackoffMs(attempt, baseMs = 250L, maxMs = 2_000L)
            scheduleContinueListening(delayMs = delay)

            // If we keep failing, escalate to the heavier resume path which can fallback away
            // from injection when the service ignores the injected audio and opens the mic.
            if (attempt >= 6) {
                synchronized(lock) {
                    resumeAttempt = maxResumeAttemptsBeforeFallback
                }
                Thread {
                    pauseForInterruption()
                    scheduleResume()
                }.start()
            }
        }
    }

    private fun startRecognizerAndCapture(
        ctx: Context,
        localeId: String,
        partialResults: Boolean,
        sampleRate: Int,
        channelCount: Int,
        allowListenerFallback: Boolean,
    ) {
        synchronized(lock) {
            lastSampleRate = sampleRate
            lastChannelCount = channelCount
        }

        // Start speech recognizer first. If audio injection is ignored and it opens the mic,
        // AudioRecord init will fail and we'll fallback to recording from onBufferReceived.
        val listener = createRecognitionListener(sampleRate, channelCount).also {
            recognitionListener = it
        }

        val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)

            // Best-effort: reduce premature end-of-speech on some devices/locales.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1200)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800)
        }

        val recognizer = SpeechRecognizer.createSpeechRecognizer(ctx)
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(listener)

        val injectionConfigured = configureAudioInjectionIfPossible(ctx, recognizerIntent, sampleRate, channelCount)
        mode = if (injectionConfigured) Mode.INJECTION else Mode.LISTENER_BUFFER

        recognizer.startListening(recognizerIntent)
        armSegmentRotate()

        if (mode == Mode.INJECTION) {
            // Try to initialize AudioRecord. If it fails (e.g. mic already in-use), fallback.
            val audio = buildAudioRecord(sampleRate)
            if (audio.state != AudioRecord.STATE_INITIALIZED) {
                audio.release()

                if (!allowListenerFallback) {
                    // Likely mic still busy or injection temporarily ignored; retry later.
                    cleanupInjectionOnly()
                    mode = null
                    runCatching { recognizer.stopListening() }
                    runCatching { recognizer.cancel() }
                    runCatching { recognizer.destroy() }
                    speechRecognizer = null
                    throw IllegalStateException("AudioRecord failed to initialize")
                }

                // Mic likely taken by recognizer (injection ignored). Fallback.
                cleanupInjectionOnly()
                mode = Mode.LISTENER_BUFFER

                runCatching { recognizer.stopListening() }
                runCatching { recognizer.cancel() }
                runCatching { recognizer.destroy() }

                val fallbackRecognizer = SpeechRecognizer.createSpeechRecognizer(ctx)
                speechRecognizer = fallbackRecognizer
                fallbackRecognizer.setRecognitionListener(listener)

                val fallbackIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)

                    // Best-effort: reduce premature end-of-speech on some devices/locales.
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                        1200
                    )
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800)
                }

                fallbackRecognizer.startListening(fallbackIntent)
                armSegmentRotate()
            } else {
                audioRecord = audio
                startAudioThread(audio, sampleRate)
            }
        }
    }

    private fun pauseForInterruption() {
        cancelContinueListening()
        cancelSegmentRotate()

        val shouldPause = synchronized(lock) {
            if (!running) return
            if (pausedForInterruption) return
            pausedForInterruption = true
            lastAmplitude = 0.0
            true
        }
        if (!shouldPause) return

        val full = synchronized(lock) {
            flushPartialLocked()
            buildFullTextLocked(null)
        }
        if (!full.isNullOrBlank()) {
            sendTranscript(full, isFinal = true)
        }

        sendState("paused")

        // Stop audio capture first to unblock reads.
        runCatching { audioRecord?.stop() }
        runCatching { audioRecord?.release() }
        audioRecord = null

        // Close injection pipe to signal EOF to recognizer.
        cleanupInjectionOnly()

        // Stop recognizer.
        mainHandler.post {
            runCatching { speechRecognizer?.stopListening() }
            runCatching { speechRecognizer?.cancel() }
            runCatching { speechRecognizer?.destroy() }
            speechRecognizer = null
        }

        // Wait for audio thread.
        runCatching { audioThread?.join(1500) }
        audioThread = null

        mode = null
    }

    private fun scheduleResume() {
        val ctx = applicationContext ?: return

        if (pausedByAudioFocus) {
            // Wait for audio focus gain (e.g. after a call) before attempting to resume.
            return
        }

        val localeId: String
        val partialResults: Boolean
        val delayMs: Long
        val runnable = Runnable {
            attemptResume(ctx)
        }

        synchronized(lock) {
            if (!running) return
            if (!pausedForInterruption) return
            if (pausedByUser) return

            localeId = lastLocaleId
            partialResults = lastPartialResults

            resumeRunnable?.let { mainHandler.removeCallbacks(it) }
            resumeRunnable = runnable
            resumeAttempt += 1
            delayMs = minOf(10_000L, 1_000L * resumeAttempt)

            // Re-assign in case caller updated while locked.
            lastLocaleId = localeId
            lastPartialResults = partialResults
        }

        mainHandler.postDelayed(runnable, delayMs)
    }

    private fun attemptResume(ctx: Context) {
        val localeId: String
        val partialResults: Boolean
        val allowListenerFallback: Boolean
        synchronized(lock) {
            if (!running) return
            if (!pausedForInterruption) return
            if (pausedByUser) return
            if (pausedByAudioFocus) return
            localeId = lastLocaleId
            partialResults = lastPartialResults
            allowListenerFallback = resumeAttempt >= maxResumeAttemptsBeforeFallback
        }

        try {
            // Ensure any stale resources are cleared.
            cleanupInjectionOnly()
            startRecognizerAndCapture(
                ctx,
                localeId,
                partialResults,
                sampleRate = 16000,
                channelCount = 1,
                allowListenerFallback = allowListenerFallback,
            )

            synchronized(lock) {
                pausedForInterruption = false
                resumeAttempt = 0
                resumeRunnable = null
            }

            sendState("resumed")
        } catch (_: Exception) {
            scheduleResume()
        }
    }

    private fun shouldAttemptResumeForError(error: Int): Boolean {
        return when (error) {
            SpeechRecognizer.ERROR_AUDIO -> true
            else -> false
        }
    }

    private fun cleanupSession(deleteFile: Boolean) {
        synchronized(lock) {
            running = false
            pausedForInterruption = false
            pausedByAudioFocus = false
            pausedByUser = false

            lastAmplitude = 0.0

            clearTranscriptStateLocked()

            continueListeningAttempt = 0
            silenceErrorStreak = 0
        }

        cancelResume()
        cancelContinueListening()
        cancelSegmentRotate()

        // Stop audio capture first to unblock reads.
        runCatching { audioRecord?.stop() }
        runCatching { audioRecord?.release() }
        audioRecord = null

        // Close injection pipe to signal EOF to recognizer.
        runCatching { pipeWriteStream?.close() }
        pipeWriteStream = null
        runCatching { pipeWritePfd?.close() }
        pipeWritePfd = null
        runCatching { pipeReadPfd?.close() }
        pipeReadPfd = null
        injectStreamId?.let { AudioPipeRegistry.clear(it) }
        injectStreamId = null

        // Stop recognizer.
        mainHandler.post {
            runCatching { speechRecognizer?.stopListening() }
            runCatching { speechRecognizer?.cancel() }
            runCatching { speechRecognizer?.destroy() }
            speechRecognizer = null
        }

        // Wait for audio thread.
        runCatching { audioThread?.join(1500) }
        audioThread = null

        // Close WAV writer.
        runCatching { wavWriter?.close() }
        wavWriter = null

        // Stop foreground service.
        applicationContext?.let { SttRecordForegroundService.stop(it) }

        abandonAudioFocus()

        if (deleteFile) {
            audioPath?.let { runCatching { File(it).delete() } }
        }
        if (deleteFile) {
            audioPath = null
        }

        mode = null
    }

    private fun requestAudioFocus() {
        val am = audioManager ?: return

        val listener = audioFocusListener ?: AudioManager.OnAudioFocusChangeListener { focusChange ->
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    pausedByAudioFocus = true
                    cancelResume()
                    Thread {
                        pauseForInterruption()
                    }.start()
                }

                AudioManager.AUDIOFOCUS_GAIN -> {
                    pausedByAudioFocus = false
                    // Resume only when an interruption pause happened.
                    if (running && pausedForInterruption && !pausedByUser) {
                        scheduleResume()
                    }
                }
            }
        }.also { audioFocusListener = it }

        if (Build.VERSION.SDK_INT >= 26) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val req = audioFocusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(listener, mainHandler)
                .setAcceptsDelayedFocusGain(false)
                .build()
                .also { audioFocusRequest = it }

            runCatching {
                am.requestAudioFocus(req)
            }
            return
        }

        @Suppress("DEPRECATION")
        runCatching {
            am.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        val listener = audioFocusListener ?: return

        pausedByAudioFocus = false
        pausedByUser = false

        if (Build.VERSION.SDK_INT >= 26) {
            val req = audioFocusRequest
            if (req != null) {
                runCatching { am.abandonAudioFocusRequest(req) }
            }
            return
        }

        @Suppress("DEPRECATION")
        runCatching { am.abandonAudioFocus(listener) }
    }

    private fun pause(result: Result) {
        val shouldPause: Boolean
        synchronized(lock) {
            if (!running) {
                pausedByUser = false
                shouldPause = false
            } else {
                pausedByUser = true
                shouldPause = !pausedForInterruption
            }
        }

        // Do not auto-resume while paused by user.
        cancelResume()
        cancelContinueListening()

        if (shouldPause) {
            Thread {
                pauseForInterruption()
            }.start()
        }

        applicationContext?.let { SttRecordForegroundService.notifyState(it, true) }

        result.success(null)
    }

    private fun resume(result: Result) {
        val ctx = applicationContext
        if (ctx == null) {
            result.success(null)
            return
        }

        val shouldAttempt: Boolean
        synchronized(lock) {
            if (!running) {
                pausedByUser = false
                shouldAttempt = false
            } else {
                pausedByUser = false
                shouldAttempt = pausedForInterruption
            }
        }

        cancelResume()

        if (shouldAttempt) {
            mainHandler.post {
                attemptResume(ctx)
            }
        }

        applicationContext?.let { SttRecordForegroundService.notifyState(it, false) }

        result.success(null)
    }

    private fun cleanupInjectionOnly() {
        runCatching { pipeWriteStream?.close() }
        pipeWriteStream = null
        runCatching { pipeWritePfd?.close() }
        pipeWritePfd = null
        runCatching { pipeReadPfd?.close() }
        pipeReadPfd = null
        injectStreamId?.let { AudioPipeRegistry.clear(it) }
        injectStreamId = null
    }

    private fun buildAudioRecord(sampleRate: Int): AudioRecord {
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT

        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding)
        val bufferSize = max(minBuffer, sampleRate / 10) * 2

        // Prefer more "raw" sources first so far-field audio (e.g. speaker playback from another
        // device) is less likely to be suppressed by voice-processing.
        val candidates = intArrayOf(
            MediaRecorder.AudioSource.UNPROCESSED,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
        )

        var last: AudioRecord? = null
        for (source in candidates) {
            val audio = runCatching {
                AudioRecord(
                    source,
                    sampleRate,
                    channelConfig,
                    encoding,
                    bufferSize
                )
            }.getOrNull() ?: continue

            if (audio.state == AudioRecord.STATE_INITIALIZED) {
                last?.runCatching { release() }
                return audio
            }

            last?.runCatching { release() }
            last = audio
        }

        // Return the last attempt (may be uninitialized); caller will handle fallback.
        return last
            ?: AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                encoding,
                bufferSize
            )
    }

    private fun startAudioThread(audio: AudioRecord, sampleRate: Int) {
        val writer = wavWriter

        audioThread = Thread {
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val encoding = AudioFormat.ENCODING_PCM_16BIT
            val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding)
            val bufferSize = max(minBuffer, sampleRate / 10) * 2
            val buffer = ByteArray(bufferSize)

            try {
                audio.startRecording()
                while (running && !pausedForInterruption) {
                    val read = audio.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        updateAmplitudeFromPcm16Le(buffer, read)
                        writer?.write(buffer, 0, read)
                        val out = pipeWriteStream
                        if (out != null) {
                            runCatching { out.write(buffer, 0, read) }
                        }
                    }
                }
            } catch (_: Exception) {
                if (running && !pausedForInterruption) {
                    Thread {
                        pauseForInterruption()
                        scheduleResume()
                    }.start()
                }
            } finally {
                runCatching { audio.stop() }
                runCatching { audio.release() }
            }
        }.also { it.start() }
    }

    private fun createRecognitionListener(sampleRate: Int, channelCount: Int): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: android.os.Bundle?) {}
            override fun onBeginningOfSpeech() {
                synchronized(lock) {
                    silenceErrorStreak = 0
                    continueListeningAttempt = 0
                }
            }

            override fun onRmsChanged(rmsdB: Float) {
                if (mode != Mode.LISTENER_BUFFER) return
                val normalized = (rmsdB / 10f).coerceIn(0f, 1f)
                lastAmplitude = normalized.toDouble()
            }

            override fun onBufferReceived(buffer: ByteArray) {
                // Fallback mode: record from recognizer's audio callback.
                if (mode != Mode.LISTENER_BUFFER) return
                val writer = wavWriter ?: return

                // Docs: big-endian 16-bit integers. Convert to little-endian for WAV.
                val le = swapEndian16(buffer)
                updateAmplitudeFromPcm16Le(le, le.size)
                writer.write(le, 0, le.size)
            }

            override fun onEndOfSpeech() {
                // In injection mode, stop feeding more audio into the current recognizer session.
                // This prevents the pipe from filling up while the recognizer is finalizing results.
                if (mode == Mode.INJECTION) {
                    cleanupInjectionOnly()
                }
            }

            override fun onError(error: Int) {
                cancelSegmentRotate()
                // Best-effort: finalize any outstanding partial before we restart.
                handleRecognitionSegment(null, isFinal = true)

                // Always reset the injection pipe for the next session.
                if (mode == Mode.INJECTION) {
                    cleanupInjectionOnly()
                }

                // Silence-related errors are common in continuous listening.
                when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH,
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                        val streak: Int
                        synchronized(lock) {
                            silenceErrorStreak += 1
                            continueListeningAttempt = 0
                            streak = silenceErrorStreak
                        }

                        val delay = computeBackoffMs(streak, baseMs = 250L, maxMs = 2_000L)
                        scheduleContinueListening(delayMs = delay)
                        return
                    }

                    // These happen when restarting too quickly or when the service is under load.
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                    SpeechRecognizer.ERROR_CLIENT -> {
                        val attempt: Int
                        synchronized(lock) {
                            continueListeningAttempt += 1
                            silenceErrorStreak = 0
                            attempt = continueListeningAttempt
                        }

                        resetSpeechRecognizerForContinueListening()
                        val delay = computeBackoffMs(attempt, baseMs = 350L, maxMs = 2_500L)
                        scheduleContinueListening(delayMs = delay)
                        return
                    }
                }

                // Forward unexpected errors to Dart (best-effort) but keep listening.
                sendStreamError("stt_error", "SpeechRecognizer error: $error")

                if (shouldAttemptResumeForError(error)) {
                    Thread {
                        pauseForInterruption()
                        scheduleResume()
                    }.start()
                    return
                }

                val attempt: Int
                synchronized(lock) {
                    continueListeningAttempt += 1
                    silenceErrorStreak = 0
                    attempt = continueListeningAttempt
                }

                resetSpeechRecognizerForContinueListening()
                val delay = computeBackoffMs(attempt, baseMs = 600L, maxMs = 3_000L)
                scheduleContinueListening(delayMs = delay)
            }

            override fun onResults(results: android.os.Bundle) {
                cancelSegmentRotate()
                val texts = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val segment = texts?.firstOrNull()
                handleRecognitionSegment(segment, isFinal = true)

                synchronized(lock) {
                    silenceErrorStreak = 0
                    continueListeningAttempt = 0
                }

                if (mode == Mode.INJECTION) {
                    cleanupInjectionOnly()
                }

                scheduleContinueListening(delayMs = 120L)
            }

            override fun onPartialResults(partialResults: android.os.Bundle) {
                val texts = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val segment = texts?.firstOrNull() ?: return

                synchronized(lock) {
                    silenceErrorStreak = 0
                    continueListeningAttempt = 0
                }

                handleRecognitionSegment(segment, isFinal = false)
            }

            override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
        }
    }

    private fun sendTranscript(text: String, isFinal: Boolean) {
        val cleaned = text.trim()
        if (cleaned.isEmpty()) return
        val sink = synchronized(lock) { eventSink }
        mainHandler.post {
            sink?.success(mapOf("event" to "transcript", "text" to cleaned, "isFinal" to isFinal))
        }
    }

    private fun clearTranscriptStateLocked() {
        transcriptBuilder.setLength(0)
        lastFinalSegment = ""
        lastPartialSegment = ""
    }

    private fun appendFinalSegmentLocked(segment: String) {
        val cleaned = segment.trim()
        if (cleaned.isEmpty()) return
        if (cleaned == lastFinalSegment) return
        if (transcriptBuilder.isNotEmpty()) {
            transcriptBuilder.append(' ')
        }
        transcriptBuilder.append(cleaned)
        lastFinalSegment = cleaned
        lastPartialSegment = ""
    }

    private fun flushPartialLocked() {
        val partial = lastPartialSegment
        if (partial.isBlank()) return
        appendFinalSegmentLocked(partial)
    }

    private fun buildFullTextLocked(currentPartial: String?): String {
        val base = transcriptBuilder.toString()
        val partial = currentPartial?.trim().orEmpty()
        if (base.isEmpty()) return partial
        if (partial.isEmpty()) return base
        if (partial == lastFinalSegment) return base
        return "$base $partial"
    }

    private fun handleRecognitionSegment(segment: String?, isFinal: Boolean) {
        val cleaned = segment?.trim().orEmpty()
        val full = synchronized(lock) {
            if (isFinal) {
                if (cleaned.isNotEmpty()) {
                    appendFinalSegmentLocked(cleaned)
                } else {
                    flushPartialLocked()
                }
                buildFullTextLocked(null)
            } else {
                if (cleaned.isEmpty()) return
                lastPartialSegment = cleaned
                buildFullTextLocked(cleaned)
            }
        }

        if (full.isBlank()) return
        sendTranscript(full, isFinal)
    }

    private fun sendState(state: String) {
        val sink = synchronized(lock) { eventSink }
        mainHandler.post {
            sink?.success(mapOf("event" to "state", "state" to state))
        }
    }

    private fun sendStreamError(code: String, message: String) {
        val sink = synchronized(lock) { eventSink }
        mainHandler.post {
            sink?.error(code, message, null)
        }
    }

    private fun setPipeWriteNonBlocking(writeEnd: ParcelFileDescriptor) {
        runCatching {
            val fd = writeEnd.fileDescriptor
            val flags = Os.fcntlInt(fd, OsConstants.F_GETFL, 0)
            Os.fcntlInt(fd, OsConstants.F_SETFL, flags or OsConstants.O_NONBLOCK)
        }
    }

    private fun configureAudioInjectionIfPossible(
        ctx: Context,
        intent: Intent,
        sampleRate: Int,
        channelCount: Int
    ): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            val pipe = ParcelFileDescriptor.createPipe()
            val readEnd = pipe[0]
            val writeEnd = pipe[1]

            // Avoid blocking the audio capture thread if the recognizer temporarily stops reading.
            setPipeWriteNonBlocking(writeEnd)

            // Use string literals to avoid runtime field issues on older Android.
            intent.putExtra("android.speech.extra.AUDIO_SOURCE", readEnd)
            intent.putExtra("android.speech.extra.AUDIO_SOURCE_CHANNEL_COUNT", channelCount)
            intent.putExtra("android.speech.extra.AUDIO_SOURCE_ENCODING", AudioFormat.ENCODING_PCM_16BIT)
            intent.putExtra("android.speech.extra.AUDIO_SOURCE_SAMPLING_RATE", sampleRate)

            pipeReadPfd = readEnd
            pipeWritePfd = writeEnd
            pipeWriteStream = ParcelFileDescriptor.AutoCloseOutputStream(writeEnd)
            return true
        }

        if (Build.VERSION.SDK_INT >= 31) {
            val pipe = ParcelFileDescriptor.createPipe()
            val readEnd = pipe[0]
            val writeEnd = pipe[1]

            // Avoid blocking the audio capture thread if the recognizer temporarily stops reading.
            setPipeWriteNonBlocking(writeEnd)

            val streamId = UUID.randomUUID().toString()
            injectStreamId = streamId
            AudioPipeRegistry.register(streamId, readEnd)

            val authority = ctx.packageName + ".stt_record_audio_pipe"
            val uri = Uri.Builder()
                .scheme("content")
                .authority(authority)
                .appendPath("audio")
                .appendPath(streamId)
                .build()

            // EXTRA_AUDIO_INJECT_SOURCE (API 31-32): expects a URI to an audio resource.
            intent.putExtra("android.speech.extra.AUDIO_INJECT_SOURCE", uri)
            intent.clipData = ClipData.newUri(ctx.contentResolver, "stt_record_audio", uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

            pipeWritePfd = writeEnd
            pipeWriteStream = ParcelFileDescriptor.AutoCloseOutputStream(writeEnd)
            return true
        }

        return false
    }

    private fun swapEndian16(src: ByteArray): ByteArray {
        val out = ByteArray(src.size)
        var i = 0
        while (i + 1 < src.size) {
            out[i] = src[i + 1]
            out[i + 1] = src[i]
            i += 2
        }
        if (src.size % 2 == 1) {
            out[src.size - 1] = src[src.size - 1]
        }
        return out
    }

    private fun updateAmplitudeFromPcm16Le(pcm: ByteArray, length: Int) {
        val usable = length - (length % 2)
        if (usable <= 0) {
            lastAmplitude = 0.0
            return
        }

        var peak = 0
        var i = 0
        while (i + 1 < usable) {
            val lo = pcm[i].toInt() and 0xFF
            val hi = pcm[i + 1].toInt()
            val sample = (hi shl 8) or lo
            val s = sample.toShort().toInt()
            val absVal = kotlin.math.abs(s)
            if (absVal > peak) peak = absVal
            i += 2
        }

        lastAmplitude = (peak / 32768.0).coerceIn(0.0, 1.0)
    }
}
