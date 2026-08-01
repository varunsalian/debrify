package com.debrify.app.tv

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

/**
 * Owns the destination and state of a single in-progress IPTV recording on the
 * native (ExoPlayer) TV player.
 *
 * The recording is produced by [RecordingDataSource], which tees the bytes
 * ExoPlayer already reads for playback into the [OutputStream] this controller
 * holds. Only the MAIN stream is captured: [shouldRecord] matches the request's
 * URI against the channel URL passed to [start], so playlist/subtitle/key
 * requests that share the same [androidx.media3.datasource.DataSource.Factory]
 * are never written.
 *
 * Destination mirrors the app's existing storage idiom
 * (MediaStoreDownloadService.createViaMediaStore): a `MediaStore.Downloads`
 * pending row under `Download/Debrify/Recordings`, made visible by clearing
 * `IS_PENDING` on [stop]. No `WRITE_EXTERNAL_STORAGE` needed on API 29+.
 *
 * Every method is safe to call from ExoPlayer's loader thread and the UI thread;
 * mutation is guarded by [lock] and [active] is volatile for the read-hot
 * [shouldRecord] path.
 */
class IptvRecordingController(private val context: Context) {

    private val lock = Any()

    @Volatile
    private var active = false

    /** The channel stream URL currently being recorded (match key). */
    private var targetUri: Uri? = null

    /** The MediaStore row (content://) we are writing into. */
    private var mediaStoreUri: Uri? = null
    private var pfd: ParcelFileDescriptor? = null
    private var output: OutputStream? = null

    /** Bytes written so far for the active recording (0 when idle). */
    var bytesWritten: Long = 0L
        private set

    val isActive: Boolean
        get() = active

    /**
     * Begin recording [streamUrl] to a new MediaStore row named [displayName].
     * Returns true on success. Never throws.
     */
    fun start(streamUrl: String, displayName: String, mimeType: String): Boolean {
        synchronized(lock) {
            if (active) return false
            return try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.Downloads.RELATIVE_PATH, "Download/Debrify/Recordings")
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                }
                val uri = context.contentResolver
                    .insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return false
                val descriptor = context.contentResolver.openFileDescriptor(uri, "rw")
                if (descriptor == null) {
                    runCatching { context.contentResolver.delete(uri, null, null) }
                    return false
                }
                output = BufferedOutputStream(FileOutputStream(descriptor.fileDescriptor))
                pfd = descriptor
                mediaStoreUri = uri
                targetUri = Uri.parse(streamUrl)
                bytesWritten = 0L
                active = true
                true
            } catch (e: Exception) {
                cleanupLocked(deleteRow = true)
                false
            }
        }
    }

    /** True when [uri] is the main stream of the active recording. */
    fun shouldRecord(uri: Uri?): Boolean {
        if (!active) return false
        val target = targetUri ?: return false
        return uri != null && uri.toString() == target.toString()
    }

    /** Append freshly-read playback bytes. Aborts the recording on write error. */
    fun write(buffer: ByteArray, offset: Int, length: Int) {
        if (length <= 0) return
        synchronized(lock) {
            val stream = output ?: return
            try {
                stream.write(buffer, offset, length)
                bytesWritten += length
            } catch (e: IOException) {
                // Disk full / row revoked: stop cleanly rather than crash playback.
                cleanupLocked(deleteRow = false)
                finalizePendingLocked(mediaStoreUri)
            }
        }
    }

    /**
     * Finish the recording and publish it (clear IS_PENDING). Returns the
     * content URI of the finished file, or null if nothing was recording.
     */
    fun stop(): Uri? {
        synchronized(lock) {
            if (!active && mediaStoreUri == null) return null
            val uri = mediaStoreUri
            cleanupLocked(deleteRow = false)
            finalizePendingLocked(uri)
            return uri
        }
    }

    /**
     * Abort the recording and delete the (unusable) partial row. Used when the
     * stream turns out to be HLS after playback started, or on fatal error.
     */
    fun abortAndDelete() {
        synchronized(lock) {
            cleanupLocked(deleteRow = true)
        }
    }

    /** Close streams and reset state. Caller holds [lock]. */
    private fun cleanupLocked(deleteRow: Boolean) {
        active = false
        runCatching { output?.flush() }
        runCatching { output?.close() }
        runCatching { pfd?.close() }
        output = null
        pfd = null
        targetUri = null
        bytesWritten = 0L
        if (deleteRow) {
            mediaStoreUri?.let { uri -> runCatching { context.contentResolver.delete(uri, null, null) } }
            mediaStoreUri = null
        }
    }

    /** Clear IS_PENDING so the finished file becomes user-visible. */
    private fun finalizePendingLocked(uri: Uri?) {
        if (uri == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            runCatching { context.contentResolver.update(uri, done, null, null) }
        }
        mediaStoreUri = null
    }
}
