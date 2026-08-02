package com.debrify.app.tv

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener

/**
 * A pass-through [DataSource] that tees the bytes ExoPlayer reads for playback
 * into an [IptvRecordingController] when a recording is active and this source
 * is serving the recorded stream.
 *
 * It forwards every call to [upstream] unchanged and only observes [read]; the
 * recorded bytes are exactly what the player consumes, so no second network
 * connection, re-auth, or extra bandwidth is involved.
 *
 * Only progressive (single continuous connection) streams produce a clean file
 * this way. HLS — where playback interleaves playlist and segment requests —
 * is gated off at the UI layer, so this data source is never asked to record
 * one.
 */
@OptIn(UnstableApi::class)
class RecordingDataSource(
    private val upstream: DataSource,
    private val controller: IptvRecordingController,
) : DataSource {

    /** The URI this source was opened for (pre-redirect), used as the match key. */
    private var openedUri: Uri? = null

    override fun addTransferListener(transferListener: TransferListener) {
        upstream.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        openedUri = dataSpec.uri
        return upstream.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val bytesRead = upstream.read(buffer, offset, length)
        if (bytesRead > 0 && controller.shouldRecord(openedUri)) {
            controller.write(buffer, offset, bytesRead)
        }
        return bytesRead
    }

    override fun getUri(): Uri? = upstream.uri

    override fun getResponseHeaders(): Map<String, List<String>> = upstream.responseHeaders

    override fun close() {
        upstream.close()
    }

    /** Wraps an upstream factory so every produced source records-on-demand. */
    @OptIn(UnstableApi::class)
    class Factory(
        private val upstreamFactory: DataSource.Factory,
        private val controller: IptvRecordingController,
    ) : DataSource.Factory {
        override fun createDataSource(): DataSource =
            RecordingDataSource(upstreamFactory.createDataSource(), controller)
    }
}
