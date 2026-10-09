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
internal class TvIptvJumpDialogCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun jumpFavoritesShowsExactProviderToastWithoutDialog() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Favorites",true,false,false)))
        set("iptvZapSourceId","provider")
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        call("showIptvChannelJumpDialog",emptyArray())
        assertSame(prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        assertEquals("Select a provider before jumping by channel number",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_SHORT,ShadowToast.getLatestToast().duration)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun jumpCustomListShowsExactProviderToastWithoutDialog() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Custom",false,false,false,true,"custom")))
        set("iptvZapSourceId","provider")
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        call("showIptvChannelJumpDialog",emptyArray())
        assertSame(prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        assertEquals("Select a provider before jumping by channel number",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_SHORT,ShadowToast.getLatestToast().duration)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun jumpVodContextDoesNotOpenDialog() {
        playing(entry().copy(isLive=false))
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        call("showIptvChannelJumpDialog",emptyArray())
        assertSame(prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun jumpInputPinsLabelsTypePaddingAndKeyboard() {
        call("showIptvChannelJumpDialog",emptyArray())
        val d=dialog()
        val i=dialogInput()
        assertEquals("Jump to channel",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals("Channel number",i.hint)
        assertEquals(android.text.InputType.TYPE_CLASS_NUMBER,i.inputType)
        assertEquals(1,i.maxLines)
        assertEquals(EditorInfo.IME_ACTION_GO,i.imeOptions)
        assertEquals(density(20),i.paddingLeft)
        assertEquals(density(14),i.paddingTop)
        assertEquals("Jump",d.getButton(AlertDialog.BUTTON_POSITIVE).text.toString())
        assertEquals("Cancel",d.getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        assertTrue("input focus="+i.isFocused+", visible="+i.isShown+", size="+i.width+"x"+i.height+", focusable="+i.isFocusable+", decor="+d.window!!.decorView.findFocus(),i.hasFocus())
        assertEquals(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,d.window!!.attributes.softInputMode and android.view.WindowManager.LayoutParams.SOFT_INPUT_MASK_STATE)
    }

    @Test fun installedJumpEditorGoSubmitsWhileDoneIsInert() {
        call("showIptvChannelJumpDialog",emptyArray())
        val input=dialogInput()
        input.setText(" 7 ")
        clearTransport()
        assertFalse(editor(input,EditorInfo.IME_ACTION_DONE))
        assertTrue(requests("requestIptvBrowse").isEmpty())
        assertTrue(editor(input,EditorInfo.IME_ACTION_GO))
        assertEquals(1,requests("requestIptvBrowse").size)
        assertEquals(7,args("requestIptvBrowse")["channelNumber"])
    }
}
