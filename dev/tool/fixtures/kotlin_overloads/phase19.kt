package com.debrify.app.tv

import android.net.Uri
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory

class AndroidTvTorrentPlayerActivity {
    @Volatile private var activeVodHeaders: Pair<Set<String>, Map<String, String>> = emptySet<String>() to emptyMap()
    @Volatile private var currentIptvHttpHeaders: Map<String, String> = emptyMap()
    @Volatile private var iptvStrictTsActive = false
    private val mediaPipelineController = TvMediaPipelineController(object : TvMediaPipelineController.Host {
        override val activeVodHeaders: Pair<Set<String>, Map<String, String>> get() = this@AndroidTvTorrentPlayerActivity.activeVodHeaders
        override val currentIptvHttpHeaders: Map<String, String> get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders
        override val iptvStrictTsActive: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive
    })
    private val identity = TvDockIdentityPresenter()
    private val playlistController = object : PlaylistHost {
        override val ottShowName: String? get() = identity.ottShowName
    }
    private fun handleMetadataUpdate(name: String) { identity.ottShowName = name }
    fun setupPlayer() {
        consume("activity")
        consume("connectivity")
        val dataSourceFactory = run {
            ResolvingDataSource.Factory(object : ResolvingDataSource.Resolver {
                override fun resolveDataSpec(spec: DataSpec): DataSpec {
                    val headers = activeVodHeaders
                    return spec.withHeaders(headers.second)
                }
            })
        }
        val finalDataSourceFactory = ResolvingDataSource.Factory(object : ResolvingDataSource.Resolver {
            override fun resolveDataSpec(spec: DataSpec): DataSpec {
                val headers = currentIptvHttpHeaders
                return spec.withHeaders(headers)
            }
        })
        val mediaSourceFactory = if (true) {
            val strictTs = DefaultExtractorsFactory()
            val aggressiveTs = DefaultExtractorsFactory()
            val iptvExtractors = object : ExtractorsFactory {
                override fun createExtractors(): Array<Extractor> =
                    (if (iptvStrictTsActive) strictTs else aggressiveTs).createExtractors()
                override fun createExtractors(uri: Uri, headers: Map<String, List<String>>): Array<Extractor> =
                    (if (iptvStrictTsActive) strictTs else aggressiveTs).createExtractors(uri, headers)
            }
            iptvExtractors
        } else { DefaultExtractorsFactory() }
    }
}

class TvMediaPipelineController(private val host: Host) {
    interface Host {
        val activeVodHeaders: Pair<Set<String>, Map<String, String>>
        val currentIptvHttpHeaders: Map<String, String>
        val iptvStrictTsActive: Boolean
    }
    fun setupPlayer() {
        consume("activity")
        consume("connectivity")
        val dataSourceFactory = run {
            ResolvingDataSource.Factory(object : ResolvingDataSource.Resolver {
                override fun resolveDataSpec(spec: DataSpec): DataSpec {
                    val headers = host.activeVodHeaders
                    return spec.withHeaders(headers.second)
                }
            })
        }
        val finalDataSourceFactory = ResolvingDataSource.Factory(object : ResolvingDataSource.Resolver {
            override fun resolveDataSpec(spec: DataSpec): DataSpec {
                val headers = host.currentIptvHttpHeaders
                return spec.withHeaders(headers)
            }
        })
        val mediaSourceFactory = if (true) {
            val strictTs = DefaultExtractorsFactory()
            val aggressiveTs = DefaultExtractorsFactory()
            val iptvExtractors = object : ExtractorsFactory {
                override fun createExtractors(): Array<Extractor> =
                    (if (host.iptvStrictTsActive) strictTs else aggressiveTs).createExtractors()
                override fun createExtractors(uri: Uri, headers: Map<String, List<String>>): Array<Extractor> =
                    (if (host.iptvStrictTsActive) strictTs else aggressiveTs).createExtractors(uri, headers)
            }
            iptvExtractors
        } else { DefaultExtractorsFactory() }
    }
}

class TvDockIdentityPresenter { @Volatile var ottShowName: String? = null }
interface PlaylistHost { val ottShowName: String? }
class TvPlaybackStartController(private val identity: TvDockIdentityPresenter) {
    private fun replacePayloadWithStremioTvItem(name: String) { identity.ottShowName = name }
}
class TvEpisodeMetadataReceiver(private val identity: TvDockIdentityPresenter) {
    private fun handleMetadataUpdate(name: String) { identity.ottShowName = name }
}

fun consume(value: String) { check(value.isNotEmpty()) }
