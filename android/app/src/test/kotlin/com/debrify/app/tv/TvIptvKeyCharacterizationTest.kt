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
internal class TvIptvKeyCharacterizationTest : TvPhase11OriginalTest() {
    private fun neutral() {
        (field("controlsOverlay") as View).visibility=View.GONE
        (field("playerView") as View).requestFocus();set("iptvZapPagingActive",false);set("controlsMenuVisible",false);set("iptvGuideVisible",false)
        clearTransport()
    }
    private fun index()=field("currentIptvIndex") as Int
    @Test fun realCHANNEL_UPZapsOnlyFirstDown() {
        neutral();assertTrue(key(KeyEvent.KEYCODE_CHANNEL_UP));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_CHANNEL_UP,repeat=1));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_CHANNEL_UP,action=KeyEvent.ACTION_UP));assertEquals(1,index())

    }
    @Test fun realCHANNEL_DOWNZapsOnlyFirstDown() {
        neutral();assertTrue(key(KeyEvent.KEYCODE_CHANNEL_DOWN));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_CHANNEL_DOWN,repeat=1));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_CHANNEL_DOWN,action=KeyEvent.ACTION_UP));assertEquals(1,index())

    }
    @Test fun realDPAD_RIGHTZapsOnlyFirstDown() {
        neutral();assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT,repeat=1));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT,action=KeyEvent.ACTION_UP));assertEquals(1,index())

    }
    @Test fun realDPAD_LEFTZapsOnlyFirstDown() {
        neutral();assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT,repeat=1));assertEquals(1,index())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT,action=KeyEvent.ACTION_UP));assertEquals(1,index())

    }
    @Test fun realDedicatedKeysStillZapWithControlsVisible() {
        neutral();show();assertTrue(field("iptvGuideVisible") as Boolean);set("controlsMenuVisible",true);assertTrue(key(KeyEvent.KEYCODE_CHANNEL_UP));assertEquals(1,index())

    }
    @Test fun realDpadDoesNotZapWithControlsVisible() {
        neutral();set("controlsMenuVisible",true);key(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(0,index());key(KeyEvent.KEYCODE_DPAD_LEFT);assertEquals(0,index())

    }
    @Test fun realDpadControlsFocusKeepsChannelAndUpUsesVodGrammar() {
        neutral();val overlay=field("controlsOverlay") as android.view.ViewGroup;overlay.visibility=View.VISIBLE
        var ancestor:View?=overlay;while(ancestor!=null){ancestor.visibility=View.VISIBLE;ancestor=ancestor.parent as? View}
        val focus=androidx.appcompat.widget.AppCompatButton(activity);overlay.addView(focus);focus.isFocusableInTouchMode=true;assertTrue("controls focus accepted",focus.requestFocus());syncFocus();assertTrue("controls ancestry: current=${activity.currentFocus}, decor=${activity.window.decorView.findFocus()}, target=$focus",call("isFocusInControlsOverlay",emptyArray()) as Boolean)
        key(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(0,index())
        channels()[0]=channels()[0].copy(isLive=false);set("controlsMenuVisible",true);key(KeyEvent.KEYCODE_DPAD_UP);assertFalse(field("iptvGuideVisible") as Boolean)

    }
    @Test fun realVodKeysCannotTuneLiveNeighbors() {
        neutral();channels()[0]=channels()[0].copy(isLive=false)
        assertFalse("VOD channel key follows ordinary dispatch",key(KeyEvent.KEYCODE_CHANNEL_UP));assertEquals(0,index());key(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(0,index())
        key(KeyEvent.KEYCODE_DPAD_UP);key(KeyEvent.KEYCODE_DPAD_UP,action=KeyEvent.ACTION_UP);assertFalse(field("iptvGuideVisible") as Boolean)

    }
    @Test fun realShortUpOpensGuideOnReleaseOnly() {
        neutral();assertTrue(key(KeyEvent.KEYCODE_DPAD_UP));assertFalse(field("iptvGuideVisible") as Boolean)
        assertTrue(key(KeyEvent.KEYCODE_DPAD_UP,action=KeyEvent.ACTION_UP));assertTrue(field("iptvGuideVisible") as Boolean)
        assertFalse(field("iptvUpPressActive") as Boolean);assertFalse(field("iptvUpLongPressHandled") as Boolean)

    }
    @Test fun realLongUpThresholdShowsJumpAndSuppressesShortRelease() {
        neutral();key(KeyEvent.KEYCODE_DPAD_UP);key(KeyEvent.KEYCODE_DPAD_UP,repeat=2);assertFalse(field("iptvUpLongPressHandled") as Boolean)
        key(KeyEvent.KEYCODE_DPAD_UP,repeat=3);assertTrue(field("iptvUpLongPressHandled") as Boolean);idle()
        assertNotNull(ShadowDialog.getLatestDialog());assertTrue(ShadowDialog.getLatestDialog().isShowing)
        key(KeyEvent.KEYCODE_DPAD_UP,action=KeyEvent.ACTION_UP);assertFalse(field("iptvGuideVisible") as Boolean)

    }
    @Test fun realRepeatedUpWithoutInitialDownDoesNotArm() {
        neutral();key(KeyEvent.KEYCODE_DPAD_UP,repeat=3);assertFalse(field("iptvUpLongPressHandled") as Boolean);key(KeyEvent.KEYCODE_DPAD_UP,action=KeyEvent.ACTION_UP);assertFalse(field("iptvGuideVisible") as Boolean)

    }
    @Test fun realGuideLongUpMovesRowFocusToSearch() {
        neutral();show();advance(180);val holder=guideList().findViewHolderForAdapterPosition(0)
        assertNotNull("real attached guide row",holder);assertTrue(holder!!.itemView.requestFocus())
        syncFocus();assertTrue("row ancestry: current=${activity.currentFocus}, decor=${activity.window.decorView.findFocus()}, target=${holder.itemView}",call("isFocusInIptvChannelList",emptyArray()) as Boolean);key(KeyEvent.KEYCODE_DPAD_UP,repeat=3);assertTrue("UP transfers focus to search",search().hasFocus());assertTrue(field("iptvAllCategorySearchActive") as Boolean)

    }
}
