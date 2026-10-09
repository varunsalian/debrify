package com.debrify.app.tv

import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import java.util.concurrent.LinkedBlockingQueue

/** Only the blocking HTTP attempt is scripted; production IO, retries and Main survive. */
@Implements(className = "com.debrify.app.subtitle.StremioSubtitleService", isInAndroidSdk = false)
class TvPhase14SubtitleFetchShadow {
    @Implementation fun attemptFetch(addon: StremioAddon, url: String): List<StremioSubtitle> =
        (responses[addon.id]?.poll() ?: error("unscripted subtitle HTTP attempt: $url")).answer(addon, url)

    companion object {
        val responses = java.util.concurrent.ConcurrentHashMap<String, LinkedBlockingQueue<TvPhase4Response<List<StremioSubtitle>>>>()
    }
}
