package vn.fighttechvn.stt_record

import android.os.ParcelFileDescriptor

internal object AudioPipeRegistry {
    private val lock = Any()
    private val readPipes: MutableMap<String, ParcelFileDescriptor> = HashMap()

    fun register(streamId: String, readPipe: ParcelFileDescriptor) {
        synchronized(lock) {
            readPipes[streamId] = readPipe
        }
    }

    fun pop(streamId: String): ParcelFileDescriptor? {
        synchronized(lock) {
            val original = readPipes.remove(streamId) ?: return null
            return try {
                val dup = ParcelFileDescriptor.dup(original.fileDescriptor)
                original.close()
                dup
            } catch (_: Exception) {
                runCatching { original.close() }
                null
            }
        }
    }

    fun clear(streamId: String) {
        synchronized(lock) {
            readPipes.remove(streamId)?.runCatching { close() }
        }
    }
}
