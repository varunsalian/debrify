package com.debrify.app.tv

import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.util.LanguageMapper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode

/** Exercise the retained defensive empty-variants branch without changing the mapper. */
@Implements(value = LanguageMapper::class, isInAndroidSdk = false)
class EmptyIptvAudioVariantsShadow {
    companion object {
        @JvmStatic @Implementation fun getLanguageVariantsForExoPlayer(langCode: String): List<String> = emptyList()
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [EmptyIptvAudioVariantsShadow::class], instrumentedPackages = ["com.debrify.app.util"])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvIptvEmptyAudioVariantsSweepTest : TvPhase11OriginalTest() {
    @Test fun emptyMapperVariantsFallsBackToExplicitLanguage() {
        assertTrue("test dependency supplies the defensive empty case", LanguageMapper.getLanguageVariantsForExoPlayer("fixture").isEmpty())
        val selector = field("trackSelector") as DefaultTrackSelector
        selector.parameters = selector.parameters.buildUpon().setPreferredAudioLanguage("old").build()
        call("setIptvPreferredAudioLang", arrayOf(stringType), "fixture")
        assertEquals(listOf("fixture"), selector.parameters.preferredAudioLanguages.toList())
    }
}
