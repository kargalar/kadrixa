package app.kadrixa

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class ProcessingLocksTest {
    @Test
    fun samePathCannotBeAcquiredByAnotherEngineUntilReleased() {
        val file = File.createTempFile("media-job", ".lock")
        try {
            val first = requireNotNull(ProcessingLocks.tryAcquire(file))
            assertNull(ProcessingLocks.tryAcquire(file))
            ProcessingLocks.release("unrelated-token")
            assertNull(ProcessingLocks.tryAcquire(file))
            ProcessingLocks.release(first)
            val second = requireNotNull(ProcessingLocks.tryAcquire(file))
            assertNotEquals(first, second)
            ProcessingLocks.release(second)
        } finally {
            file.delete()
        }
    }

    @Test
    fun independentCapturesCanBeProcessedConcurrently() {
        val firstFile = File.createTempFile("media-job-a", ".lock")
        val secondFile = File.createTempFile("media-job-b", ".lock")
        val first = requireNotNull(ProcessingLocks.tryAcquire(firstFile))
        val second = requireNotNull(ProcessingLocks.tryAcquire(secondFile))
        try {
            assertNotEquals(first, second)
        } finally {
            ProcessingLocks.release(first)
            ProcessingLocks.release(second)
            firstFile.delete()
            secondFile.delete()
        }
    }
}
