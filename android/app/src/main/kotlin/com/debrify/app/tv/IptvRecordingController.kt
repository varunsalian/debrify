package com.debrify.app.tv

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
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
 * API 29 is also the FLOOR: `MediaStore.Downloads` does not exist before Q, so
 * merely touching [MediaStore.Downloads.EXTERNAL_CONTENT_URI] on an older
 * device throws NoClassDefFoundError — an Error, which the catch below would
 * not hold. The app ships no `WRITE_EXTERNAL_STORAGE` either, so there is no
 * legacy destination to fall back to; [isSupported] gates the whole feature
 * off instead, and the UI hides the button.
 *
 * Every method is safe to call from ExoPlayer's loader thread and the UI thread;
 * mutation is guarded by [lock] and [active] is volatile for the read-hot
 * [shouldRecord] path.
 */
class IptvRecordingController(private val context: Context) {

    companion object {
        /** MediaStore.Downloads (the only destination we have) is API 29+. */
        val isSupported: Boolean
            get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    private val lock = Any()

    @Volatile
    private var active = false

    /** The channel stream URL currently being recorded (match key). */
    private var targetUri: Uri? = null

    /** The MediaStore row (content://) we are writing into. */
    private var mediaStoreUri: Uri? = null
    private var pfd: ParcelFileDescriptor? = null
    private var output: OutputStream? = null

    /**
     * Finished rows whose IS_PENDING could not be cleared. Held — not
     * dropped — because each row is the only copy of its bytes: forgetting a
     * URI would orphan an invisible file this controller could neither
     * publish nor delete. A LIST, not a single slot: while storage is
     * misbehaving, recording B can finish before A's row is recovered, and a
     * single slot would silently orphan A. [retryPendingPublish] retries all.
     */
    private val unpublishedUris = mutableListOf<Uri>()

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Invoked on the MAIN thread when a recording ends by itself — a write
     * error, never a user stop. Without it the UI would keep offering "Stop"
     * for a recording that is already over, and the next press would silently
     * start a second one.
     */
    var onAborted: (() -> Unit)? = null

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
            // Pre-Q: no MediaStore.Downloads class to reference at all. Bail
            // BEFORE any instruction that would resolve it.
            if (!isSupported) return false
            // Earlier rows that failed to publish get one more attempt now,
            // against a provider that may since have recovered.
            retryUnpublishedLocked()
            return try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, "Download/Debrify/Recordings")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = context.contentResolver
                    .insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return false
                // Publish each resource to the fields the instant it exists, so
                // a throw from ANY later step (openFileDescriptor, the stream
                // constructors) hands cleanupLocked something to close and a
                // row to delete. Assigning only after the last step would leak
                // the pending row and the fd on exactly those failures.
                mediaStoreUri = uri
                // Durable from CREATION, not from publish-failure: if the
                // process dies mid-recording, onDestroy never runs and this
                // in-memory state is gone — the app-start sweep then finds the
                // row here and publishes the partial (or deletes an empty one).
                com.debrify.app.recording.TeeUnpublishedStore.add(context, uri)
                val descriptor = context.contentResolver.openFileDescriptor(uri, "rw")
                if (descriptor == null) {
                    cleanupLocked(deleteRow = true)
                    return false
                }
                pfd = descriptor
                output = BufferedOutputStream(FileOutputStream(descriptor.fileDescriptor))
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
                // The recording is over even though the user never asked — tell
                // the UI, which is still showing "Stop".
                mainHandler.post { onAborted?.invoke() }
            }
        }
    }

    /** What [stop] did: the row it wrote (null when nothing was recording),
     *  and whether that row could actually be made user-visible. */
    data class StopResult(val uri: Uri?, val published: Boolean) {
        val wasRecording: Boolean get() = uri != null
    }

    /**
     * Finish the recording and publish it (clear IS_PENDING). Callers must
     * read [StopResult.published] before telling the user it was saved —
     * publishing can fail, and an unpublished row is invisible in Downloads.
     */
    fun stop(): StopResult {
        synchronized(lock) {
            if (!active && mediaStoreUri == null) return StopResult(null, false)
            val uri = mediaStoreUri
            cleanupLocked(deleteRow = false)
            val published = finalizePendingLocked(uri)
            return StopResult(uri, published)
        }
    }

    /** True when a previous recording is written but still invisible. */
    val hasUnpublishedRecording: Boolean
        get() = synchronized(lock) { unpublishedUris.isNotEmpty() }

    /**
     * Retry publishing rows an earlier [stop] could not make visible. Returns
     * true when at least one was recovered, so the caller can say so.
     */
    fun retryPendingPublish(): Boolean {
        synchronized(lock) {
            return retryUnpublishedLocked() > 0
        }
    }

    /** Retry every stashed row; returns how many published. Caller holds lock. */
    private fun retryUnpublishedLocked(): Int {
        if (unpublishedUris.isEmpty()) return 0
        val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        var recovered = 0
        val it = unpublishedUris.iterator()
        while (it.hasNext()) {
            val uri = it.next()
            val published = runCatching {
                context.contentResolver.update(uri, done, null, null)
            }.getOrDefault(0) > 0
            if (published) {
                it.remove()
                com.debrify.app.recording.TeeUnpublishedStore.remove(context, uri)
                recovered++
            }
        }
        return recovered
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
            mediaStoreUri?.let { uri ->
                runCatching { context.contentResolver.delete(uri, null, null) }
                // A deleted row must not be "recovered" by the app-start sweep.
                com.debrify.app.recording.TeeUnpublishedStore.remove(context, uri)
            }
            mediaStoreUri = null
        }
    }

    /**
     * Clear IS_PENDING so the finished file becomes user-visible. Returns
     * false when the row could NOT be published (update threw or matched no
     * rows — ejected volume, provider refusal).
     *
     * The row is deliberately KEPT on failure. Unlike the phone path, which
     * copies from an app-private file it can fall back to, these bytes exist
     * only here: deleting the row would destroy the entire recording, so an
     * invisible row the system reaps later is the lesser loss. The URI joins
     * [unpublishedUris] so [retryPendingPublish] can still reach it — AND the
     * persisted [com.debrify.app.recording.TeeUnpublishedStore], because this
     * list dies with the activity and finalization often happens in onDestroy
     * itself; the app-start sweep is the retry path that survives that.
     */
    private fun finalizePendingLocked(uri: Uri?): Boolean {
        if (uri == null) return false
        val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        val published = runCatching {
            context.contentResolver.update(uri, done, null, null)
        }.getOrDefault(0) > 0
        if (uri == mediaStoreUri) mediaStoreUri = null
        if (published) {
            unpublishedUris.remove(uri)
            com.debrify.app.recording.TeeUnpublishedStore.remove(context, uri)
        } else {
            if (!unpublishedUris.contains(uri)) unpublishedUris.add(uri)
            com.debrify.app.recording.TeeUnpublishedStore.add(context, uri)
        }
        return published
    }
}
