package vn.fighttechvn.stt_record

import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal class WavWriter(
    private val file: File,
    private val sampleRate: Int,
    private val channelCount: Int,
    private val bitsPerSample: Int = 16
) : Closeable {
    private var outputStream: FileOutputStream? = FileOutputStream(file)
    private var dataBytes: Long = 0

    init {
        writeHeaderPlaceholder()
    }

    fun write(pcm: ByteArray, offset: Int, length: Int) {
        val out = outputStream ?: return
        out.write(pcm, offset, length)
        dataBytes += length.toLong()
    }

    override fun close() {
        val out = outputStream
        outputStream = null
        runCatching { out?.flush() }
        runCatching { out?.close() }
        updateHeader()
    }

    private fun writeHeaderPlaceholder() {
        val byteRate = sampleRate * channelCount * bitsPerSample / 8
        val blockAlign = channelCount * bitsPerSample / 8

        val header = ByteArray(44)
        val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)

        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(0) // chunkSize placeholder
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16) // subchunk1Size
        buffer.putShort(1) // PCM
        buffer.putShort(channelCount.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(0) // subchunk2Size placeholder

        outputStream?.write(header)
    }

    private fun updateHeader() {
        // WAV uses 32-bit lengths. If dataBytes exceeds Int, the file will be invalid.
        val dataSize = dataBytes.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        val riffSize = 36 + dataSize

        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(4)
            raf.writeIntLE(riffSize)
            raf.seek(40)
            raf.writeIntLE(dataSize)
        }
    }
}

private fun RandomAccessFile.writeIntLE(value: Int) {
    write(
        byteArrayOf(
            (value and 0xFF).toByte(),
            ((value shr 8) and 0xFF).toByte(),
            ((value shr 16) and 0xFF).toByte(),
            ((value shr 24) and 0xFF).toByte()
        )
    )
}
