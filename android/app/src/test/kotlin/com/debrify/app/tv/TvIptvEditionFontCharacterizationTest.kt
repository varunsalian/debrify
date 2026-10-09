package com.debrify.app.tv
import android.view.View
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.TextView
import android.widget.ImageView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28], instrumentedPackages=["com.debrify.app.tv.AndroidTvTorrentPlayerActivity","com.debrify.app.tv.TvIptvGuideChromeController"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvEditionFontCharacterizationTest : TvPhase12OriginalTest() {
    override val phase12Style = GuideStyle.EDITION

    @Test fun cachedSerifAndItalicFontsPinTitlesAndKickers() {
        val tokens=GuideTokens.of(phase12Style)!!
        @Suppress("UNCHECKED_CAST") val cache=field("guideTypefaces") as MutableMap<String,android.graphics.Typeface?>
        val serif=android.graphics.Typeface.create("serif",android.graphics.Typeface.BOLD)
        val italic=android.graphics.Typeface.create("serif",android.graphics.Typeface.NORMAL)
        cache[tokens.headlineFont!!]=serif
        cache[tokens.captionFont!!]=italic
        for(id in listOf(R.id.iptv_guide_kicker,R.id.iptv_epg_kicker))activity.findViewById<TextView>(id).typeface=android.graphics.Typeface.DEFAULT
        call("applyGuideStyle",emptyArray())
        assertSame(serif,activity.findViewById<TextView>(R.id.iptv_guide_title).typeface)
        assertSame(serif,t("iptvEpgChannelName").typeface)
        for(id in listOf(R.id.iptv_guide_kicker,R.id.iptv_epg_kicker))assertEquals(android.graphics.Typeface.ITALIC,activity.findViewById<TextView>(id).typeface.style)
    }

    @Test fun cachedEditionFontsFlowThroughChannelAndScheduleAdapters() {
        val tokens=GuideTokens.of(phase12Style)!!
        @Suppress("UNCHECKED_CAST") val cache=field("guideTypefaces") as MutableMap<String,android.graphics.Typeface?>
        val serif=android.graphics.Typeface.create("serif",android.graphics.Typeface.BOLD)
        val caption=android.graphics.Typeface.create("serif",android.graphics.Typeface.ITALIC)
        cache[tokens.headlineFont!!]=serif
        cache[tokens.captionFont!!]=caption
        call("setupIptvOverlay",emptyArray())
        assertSame(serif,org.robolectric.util.ReflectionHelpers.getField<android.graphics.Typeface?>(boundAdapter(),"headlineTypeface"))
        assertSame(caption,org.robolectric.util.ReflectionHelpers.getField<android.graphics.Typeface?>(boundAdapter(),"captionTypeface"))
        assertSame(serif,org.robolectric.util.ReflectionHelpers.getField<android.graphics.Typeface?>(epgAdapter(),"headlineTypeface"))
    }
}
