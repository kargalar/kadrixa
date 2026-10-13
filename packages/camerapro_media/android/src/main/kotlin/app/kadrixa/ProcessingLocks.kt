package app.kadrixa

import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.UUID

/** JVM ownership prevents overlapping isolates; file locks also protect other processes. */
object ProcessingLocks {
    private data class HeldLock(val path: String, val file: RandomAccessFile, val lock: FileLock)
    private val held = mutableMapOf<String, HeldLock>()

    @Synchronized
    fun tryAcquire(file: File): String? {
        val path = file.canonicalPath
        // Do not open/close another descriptor for an already locked file: POSIX releases
        // process locks when ANY descriptor for that file is closed.
        if (held.values.any { it.path == path }) return null
        val handle = RandomAccessFile(file, "rw")
        try {
            val lock = handle.channel.tryLock()
            if (lock == null) {
                handle.close()
                return null
            }
            val token = UUID.randomUUID().toString()
            held[token] = HeldLock(path, handle, lock)
            return token
        } catch (error: Exception) {
            handle.close()
            throw error
        }
    }

    @Synchronized
    fun release(token: String) {
        val owned = held.remove(token) ?: return
        try {
            owned.lock.release()
        } finally {
            owned.file.close()
        }
    }
}
