package com.debrify.app.tv

import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import org.robolectric.annotation.RealObject
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers.ClassParameter
import kotlin.coroutines.Continuation
import com.debrify.app.subtitle.StremioSubtitleService
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import java.util.concurrent.LinkedBlockingQueue

/** Only the blocking HTTP attempt is scripted; production IO, retries and Main survive. */
@Implements(className = "com.debrify.app.subtitle.StremioSubtitleService", isInAndroidSdk = false)
class TvPhase14SubtitleFetchShadow {
    @RealObject private lateinit var service: StremioSubtitleService

    data class FetchArguments(val type: String, val imdb: String, val season: Int?, val episode: Int?)

    /** Record the caller boundary, then preserve the real suspend/IO/retry implementation. */
    @Implementation fun fetchSubtitlesForAddon(
        addon: StremioAddon, type: String, imdb: String, season: Int?, episode: Int?,
        continuation: Continuation<List<StremioSubtitle>>
    ): Any? {
        invocations.add(FetchArguments(type, imdb, season, episode))
        return Shadow.directlyOn<Any>(service, "com.debrify.app.subtitle.StremioSubtitleService", "fetchSubtitlesForAddon",
            ClassParameter.from(StremioAddon::class.java, addon), ClassParameter.from(String::class.java, type),
            ClassParameter.from(String::class.java, imdb), ClassParameter.from(Int::class.javaObjectType, season),
            ClassParameter.from(Int::class.javaObjectType, episode), ClassParameter.from(Continuation::class.java, continuation))
    }

    @Implementation fun attemptFetch(addon: StremioAddon, url: String): List<StremioSubtitle> =
        (responses[addon.id]?.poll() ?: error("unscripted subtitle HTTP attempt: $url")).answer(addon, url)

    companion object {
        val invocations = java.util.concurrent.ConcurrentLinkedQueue<FetchArguments>()
        val responses = java.util.concurrent.ConcurrentHashMap<String, LinkedBlockingQueue<TvPhase4Response<List<StremioSubtitle>>>>()
    }
}
