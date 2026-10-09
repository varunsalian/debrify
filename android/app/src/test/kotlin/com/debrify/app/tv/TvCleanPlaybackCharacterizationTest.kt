package com.debrify.app.tv

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvCleanPlaybackCharacterizationTest : TvPhase16OriginalTest() {
    private val flags = listOf("controlsMenuVisible", "seekbarVisible", "playlistVisible", "iptvGuideVisible", "stremioTvGuideVisible")
    private val panels = listOf("subtitlePanel", "linePickerOverlay", "syncOverlay", "unifiedMenu", "sourceBrowser")
    private fun clean(): Boolean = runOriginal("isCleanPlaybackState") as Boolean
    private fun allClear() {
        flags.forEach { set(it, false) }
        panels.forEach { name -> field(name)?.let { TvPlayerOriginalAccess.set(it, "isVisible", false) } }
        v("nextOverlay").visibility = View.GONE; v("pikPakReactivationIndicator").visibility = View.GONE
        assertTrue("all twelve blockers independently cleared", clean())
    }
    private fun flag(name: String) {
        allClear(); set(name, true)
        assertFalse("$name alone blocks clean playback", clean())
        set(name, false); assertTrue(clean())
    }
    private fun panel(name: String) {
        allClear()
        val instance = field(name) ?: makePanel(name).also { set(name, it) }
        TvPlayerOriginalAccess.set(instance, "isVisible", true)
        assertFalse("$name alone blocks clean playback", clean())
        TvPlayerOriginalAccess.set(instance, "isVisible", false); assertTrue(clean())
    }
    private fun makePanel(name: String): Any {
        val type = AndroidTvTorrentPlayerActivity::class.java.getDeclaredField(name).type
        val constructor = type.constructors.filter { c -> c.parameterTypes.none { it.name.endsWith("DefaultConstructorMarker") } }.minBy { it.parameterCount }
        val position: () -> Long = { 0L }
        val applied: (Long) -> Unit = {}
        return constructor.newInstance(*constructor.parameterTypes.map { t -> when {
            Context::class.java.isAssignableFrom(t) -> activity
            t == ViewGroup::class.java || t == View::class.java -> FrameLayout(activity).apply {
                addView(View(activity).apply { id = com.debrify.app.R.id.unified_scrim })
                addView(View(activity).apply { id = com.debrify.app.R.id.unified_panel })
            }
            View::class.java.isAssignableFrom(t) -> t.getConstructor(Context::class.java).newInstance(activity)
            t == Runnable::class.java -> Runnable {}
            t.name == "kotlin.jvm.functions.Function0" -> position
            t.name == "kotlin.jvm.functions.Function1" -> applied
            t == List::class.java -> emptyList<String>()
            else -> Proxy.newProxyInstance(t.classLoader, arrayOf(t)) { _, method, _ -> when (method.returnType) {
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                List::class.java -> emptyList<Any>()
                else -> null
            } }
        } }.toTypedArray())
    }
    @Test fun noVisibleBlockerIsClean() { allClear(); panels.forEach { set(it, null) }; assertTrue(clean()) }
    @Test fun controlsAloneBlock() = flag("controlsMenuVisible")
    @Test fun legacySeekbarAloneBlocks() = flag("seekbarVisible")
    @Test fun playlistAloneBlocks() = flag("playlistVisible")
    @Test fun iptvGuideAloneBlocks() = flag("iptvGuideVisible")
    @Test fun stremioGuideAloneBlocks() = flag("stremioTvGuideVisible")
    @Test fun subtitlePanelAloneBlocks() = panel("subtitlePanel")
    @Test fun linePickerAloneBlocks() = panel("linePickerOverlay")
    @Test fun syncOverlayAloneBlocks() = panel("syncOverlay")
    @Test fun unifiedMenuAloneBlocks() = panel("unifiedMenu")
    @Test fun sourceBrowserAloneBlocks() = panel("sourceBrowser")
    @Test fun nextOverlayAloneBlocksOnlyAtVisible() {
        allClear(); v("nextOverlay").visibility = View.VISIBLE; assertFalse(clean())
        v("nextOverlay").visibility = View.INVISIBLE; assertTrue(clean())
    }
    @Test fun pikPakIndicatorAloneBlocksOnlyAtVisible() {
        allClear(); v("pikPakReactivationIndicator").visibility = View.VISIBLE; assertFalse(clean())
        v("pikPakReactivationIndicator").visibility = View.INVISIBLE; assertTrue(clean())
    }
}
