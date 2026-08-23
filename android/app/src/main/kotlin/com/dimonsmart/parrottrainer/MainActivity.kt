package com.dimonsmart.parrottrainer

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.view.WindowManager
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "parrot_trainer/screen")
            .setMethodCallHandler { call, result ->
                if (call.method != "setKeepScreenOn") {
                    if (call.method == "setBackgroundTrainingEnabled") {
                        TrainingBackgroundService.setEnabled(
                            this,
                            call.argument<Boolean>("enabled") == true,
                        )
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (call.argument<Boolean>("enabled") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "parrot_trainer/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidSdkInt") {
                    result.success(Build.VERSION.SDK_INT)
                    return@setMethodCallHandler
                }
                if (call.method != "convertWavToM4a") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("sourcePath")
                val destinationPath = call.argument<String>("destinationPath")
                if (sourcePath.isNullOrBlank() || destinationPath.isNullOrBlank()) {
                    result.error("invalid_paths", "Audio paths are required", null)
                    return@setMethodCallHandler
                }
                Thread {
                    runCatching {
                        convertWavToM4a(sourcePath, destinationPath)
                        val destination = File(destinationPath)
                        check(destination.isFile && destination.length() > 0L) {
                            "M4A conversion produced an empty file"
                        }
                    }
                        .onSuccess { runOnUiThread { result.success(null) } }
                        .onFailure { error ->
                            File(destinationPath).delete()
                            runOnUiThread {
                                result.error("audio_conversion_failed", error.message, null)
                            }
                        }
                }.start()
            }
    }

    private fun convertWavToM4a(sourcePath: String, destinationPath: String) {
        check(wavAudioPayloadSize(sourcePath) >= 1024) { "WAV file has no audio samples" }
        val extractor = MediaExtractor()
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(sourcePath)
            val inputTrack = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index)
                    .getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: error("WAV file has no audio track")
            extractor.selectTrack(inputTrack)
            val inputFormat = extractor.getTrackFormat(inputTrack)
            val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            val outputFormat = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                sampleRate,
                channelCount,
            ).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, 64_000 * channelCount)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
            }
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder = codec
            codec.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            File(destinationPath).parentFile?.mkdirs()
            val mediaMuxer = MediaMuxer(
                destinationPath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )
            muxer = mediaMuxer
            val bufferInfo = MediaCodec.BufferInfo()
            var outputTrack = -1
            var inputEnded = false
            var outputEnded = false

            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)
                            ?: error("AAC encoder has no input buffer")
                        val size = extractor.readSampleData(inputBuffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                size,
                                extractor.sampleTime.coerceAtLeast(0),
                                0,
                            )
                            extractor.advance()
                        }
                    }
                }

                when (val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        check(!muxerStarted) { "AAC output format changed twice" }
                        outputTrack = mediaMuxer.addTrack(codec.outputFormat)
                        mediaMuxer.start()
                        muxerStarted = true
                    }
                    else -> if (outputIndex >= 0) {
                        val outputBuffer = codec.getOutputBuffer(outputIndex)
                            ?: error("AAC encoder has no output buffer")
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                            bufferInfo.size = 0
                        }
                        if (bufferInfo.size > 0) {
                            check(muxerStarted) { "AAC muxer was not started" }
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            mediaMuxer.writeSampleData(
                                outputTrack,
                                outputBuffer,
                                bufferInfo,
                            )
                        }
                        outputEnded =
                            bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } catch (error: Throwable) {
            File(destinationPath).delete()
            throw error
        } finally {
            extractor.release()
            runCatching { encoder?.stop() }
            encoder?.release()
            if (muxerStarted) runCatching { muxer?.stop() }
            muxer?.release()
        }
    }

    private fun wavAudioPayloadSize(path: String): Long {
        val file = File(path)
        if (!file.isFile || file.length() < 12) return 0
        file.inputStream().use { input ->
            val header = ByteArray(12)
            if (input.read(header) != header.size ||
                String(header, 0, 4) != "RIFF" ||
                String(header, 8, 4) != "WAVE"
            ) return 0
            val chunkHeader = ByteArray(8)
            var position = 12L
            while (input.read(chunkHeader) == chunkHeader.size) {
                position += chunkHeader.size
                val size = (chunkHeader[4].toLong() and 0xff) or
                    ((chunkHeader[5].toLong() and 0xff) shl 8) or
                    ((chunkHeader[6].toLong() and 0xff) shl 16) or
                    ((chunkHeader[7].toLong() and 0xff) shl 24)
                if (String(chunkHeader, 0, 4) == "data") {
                    return if (size <= file.length() - position) size else 0
                }
                val toSkip = size + (size and 1)
                var skipped = 0L
                while (skipped < toSkip) {
                    val count = input.skip(toSkip - skipped)
                    if (count <= 0) return 0
                    skipped += count
                }
                position += toSkip
            }
        }
        return 0
    }
}
