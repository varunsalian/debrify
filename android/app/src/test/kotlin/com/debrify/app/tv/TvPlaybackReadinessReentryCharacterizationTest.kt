package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.After
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase18ReadinessShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackReadinessReentryCharacterizationTest : TvPhase18OriginalTest() {
    @After fun clearReentry() { TvPhase18ReadinessEvents.reenter=false }
    @Test fun oldReadyDuringPreparationIsClearedBeforeInstallPlain() {
        TvPhase18ReadinessEvents.calls=0; TvPhase18ReadinessEvents.reenter=true
         probe.onEvent={ if(it.startsWith("media:") || it=="merged") { assertEquals(2,TvPhase18ReadinessEvents.calls); assertFalse(readiness().canSelect(true)) } }
         directItem(); assertEquals(2,TvPhase18ReadinessEvents.calls); assertEquals(1,probe.events.count { it.startsWith("media:") || it=="merged" })
    }

    @Test fun oldReadyDuringPreparationIsClearedBeforeInstallMerged() {
        TvPhase18ReadinessEvents.calls=0; TvPhase18ReadinessEvents.reenter=true
         probe.onEvent={ if(it.startsWith("media:") || it=="merged") { assertEquals(2,TvPhase18ReadinessEvents.calls); assertFalse(readiness().canSelect(true)) } }
         payload(p2Item().copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4")); directItem(); assertEquals(2,TvPhase18ReadinessEvents.calls); assertEquals(1,probe.events.count { it.startsWith("media:") || it=="merged" })
    }

    @Test fun oldReadyDuringPreparationIsClearedBeforeInstallPikPak() {
        TvPhase18ReadinessEvents.calls=0; TvPhase18ReadinessEvents.reenter=true
         probe.onEvent={ if(it.startsWith("media:") || it=="merged") { assertEquals(2,TvPhase18ReadinessEvents.calls); assertFalse(readiness().canSelect(true)) } }
         pikpak(); assertEquals(2,TvPhase18ReadinessEvents.calls); assertEquals(1,probe.events.count { it.startsWith("media:") || it=="merged" })
    }

    @Test fun oldReadyDuringPreparationIsClearedBeforeInstallTrio() {
        TvPhase18ReadinessEvents.calls=0; TvPhase18ReadinessEvents.reenter=true
         probe.onEvent={ if(it.startsWith("media:") || it=="merged") { assertEquals(2,TvPhase18ReadinessEvents.calls); assertFalse(readiness().canSelect(true)) } }
         call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),p2Guide(),emptyMap<String,Any>(),"https://tv.invalid/new.mp4","Next",false); assertEquals(2,TvPhase18ReadinessEvents.calls); assertEquals(1,probe.events.count { it.startsWith("media:") || it=="merged" })
    }
}

/** Observation of a borrowed dependency's READY during preparation, not a replacement start body. */
internal object TvPhase18ReadinessEvents {
    var calls=0
    var reenter=false
}

@org.robolectric.annotation.Implements(SubtitleTrackReadiness::class, isInAndroidSdk=false)
internal class TvPhase18ReadinessShadow {
    @org.robolectric.annotation.RealObject private lateinit var real: SubtitleTrackReadiness
    @org.robolectric.annotation.Implementation fun onMediaReplacement() {
        org.robolectric.shadow.api.Shadow.directlyOn<Unit>(real,"com.debrify.app.tv.SubtitleTrackReadiness","onMediaReplacement")
        TvPhase18ReadinessEvents.calls++
        if (TvPhase18ReadinessEvents.reenter && TvPhase18ReadinessEvents.calls==1) real.onReady()
    }
}
