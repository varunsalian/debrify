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
internal class TvIptvChromeFontCharacterizationTest : TvPhase12OriginalTest() {
    override val phase12Style = GuideStyle.CONSOLE

    @Test fun cachedConcreteFontsFlowThroughBothAdaptersAndOverlay() {
        val tokens=GuideTokens.of(phase12Style)!!
        @Suppress("UNCHECKED_CAST") val cache=field("guideTypefaces") as MutableMap<String,android.graphics.Typeface?>
        val mono=android.graphics.Typeface.create("monospace",android.graphics.Typeface.BOLD)
        val name=android.graphics.Typeface.create("sans-serif",android.graphics.Typeface.ITALIC)
        cache[tokens.monoFont!!]=mono
        cache[tokens.nameFont!!]=name
        call("setupIptvOverlay",emptyArray())
        fun property(o: Any,n: String)=o.javaClass.getDeclaredField(n).apply{isAccessible=true}.get(o)
        assertSame(mono,property(boundAdapter(),"monoTypeface"))
        assertSame(mono,property(epgAdapter(),"monoTypeface"))
        assertSame(name,property(boundAdapter(),"nameTypeface"))
        for(id in listOf(R.id.iptv_nav_browse,R.id.iptv_guide_kicker,R.id.iptv_epg_kicker))assertSame(mono,activity.findViewById<TextView>(id).typeface)
        assertSame(mono,search().typeface)
        assertSame(name,activity.findViewById<TextView>(R.id.iptv_guide_title).typeface)
        assertSame(name,t("iptvEpgChannelName").typeface)
    }
}
