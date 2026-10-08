package com.debrify.app.tv
import android.view.View
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowToast
import org.robolectric.util.ReflectionHelpers
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvVodCallerCharacterizationTest : TvPhase11OriginalTest() {
    override fun bootstrapJson() = super.bootstrapJson().put("contentType","episodes")
        .put("channels",org.json.JSONArray(listOf(org.json.JSONObject(rawChannel(live=false)),org.json.JSONObject(rawChannel("Next",2,live=false)))))
    @Test fun episodeButtonsUseInstalledNavigationCallers() {
        val entries=mutableListOf(channel(live=false).copy(logoUrl=null),channel(url="https://next.invalid",live=false).copy(logoUrl=null));set("iptvChannels",entries);set("currentIptvIndex",0);call("updateIptvEpisodeControls",emptyArray())
        (field("iptvNextButton") as View).performClick();assertEquals(1,field("currentIptvIndex"));assertEquals(entries[1].url,args("recordIptvWatch")["url"])
        (field("iptvPrevButton") as View).performClick();assertEquals(0,field("currentIptvIndex"))

    }
}
