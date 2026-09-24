package com.debrify.app.tv

import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener

/**
 * Preserve the pre-0.9.1 transport for ordinary VOD requests. Requests carrying
 * headers use the protected transport, which checks credentials on every hop.
 * Selection happens after header resolution, on EVERY open (including segment
 * loads, seeks and source switches), never once for the player's lifetime.
 */
internal class VodHttpDataSource private constructor(
    private val standardFactory: DataSource.Factory,
    private val protectedFactory: DataSource.Factory,
) : DataSource {
    private var upstream: DataSource? = null
    private val listeners = linkedSetOf<TransferListener>()

    class Factory(
        private val standardFactory: DataSource.Factory,
        private val protectedFactory: DataSource.Factory,
    ) : DataSource.Factory {
        override fun createDataSource(): DataSource =
            VodHttpDataSource(standardFactory, protectedFactory)
    }

    override fun addTransferListener(transferListener: TransferListener) {
        if (listeners.add(transferListener)) {
            upstream?.addTransferListener(transferListener)
        }
    }

    override fun open(dataSpec: DataSpec): Long {
        check(upstream == null) { "Close the previous request before opening another" }
        val factory = if (dataSpec.httpRequestHeaders.isEmpty()) {
            standardFactory
        } else {
            protectedFactory
        }
        val source = factory.createDataSource()
        // Keep the delegate even if open throws: Media3 calls close after a
        // failed open too, and the transport may have resources to release.
        upstream = source
        listeners.forEach(source::addTransferListener)
        return source.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        checkNotNull(upstream) { "No open request" }.read(buffer, offset, length)

    override fun getUri(): Uri? = upstream?.uri

    override fun getResponseHeaders(): Map<String, List<String>> =
        upstream?.responseHeaders ?: emptyMap()

    override fun close() {
        try {
            upstream?.close()
        } finally {
            upstream = null
        }
    }
}
