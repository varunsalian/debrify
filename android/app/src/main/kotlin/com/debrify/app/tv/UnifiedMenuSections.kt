package com.debrify.app.tv

import android.content.Context
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings

/**
 * Shared builders for unified-menu columns whose logic is identical across both
 * TV players (the Kotlin torrent player and the Java Torbox player), so the two
 * can't drift. Only the subtitle-appearance column lives here today — audio,
 * subtitles and sources differ enough per player (per-addon grouping, sources,
 * inline vs dialog search) that sharing them would cost more than it saves.
 */
object UnifiedMenuSections {

    /**
     * The live subtitle "Appearance" column: Size / Style / Text colour /
     * Outline colour / Background / Position / Font / Bold / Reset. Every tweak
     * mutates the shared [SubtitleSettings] / [SubtitleFontManager] then runs
     * [onChanged] so the caller can re-apply the style to its player.
     */
    @JvmStatic
    fun appearanceRows(ctx: Context, onChanged: Runnable): List<UnifiedMenuController.Row> {
        val color = SubtitleSettings.getCurrentColor(ctx)
        val outline = SubtitleSettings.getCurrentOutlineColor(ctx)
        return listOf(
            UnifiedMenuController.Row("Size", value = SubtitleSettings.getCurrentSize(ctx).label,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleSizeUp(ctx) else SubtitleSettings.cycleSizeDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Style", value = SubtitleSettings.getCurrentStyle(ctx).label,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleStyleUp(ctx) else SubtitleSettings.cycleStyleDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Text colour", value = color.label, swatch = color.color,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleColorUp(ctx) else SubtitleSettings.cycleColorDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Outline colour", value = outline.label, swatch = outline.color,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleOutlineColorUp(ctx) else SubtitleSettings.cycleOutlineColorDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Background", value = SubtitleSettings.getCurrentBg(ctx).label,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleBgUp(ctx) else SubtitleSettings.cycleBgDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Position", value = SubtitleSettings.getCurrentElevation(ctx).label,
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleSettings.cycleElevationUp(ctx) else SubtitleSettings.cycleElevationDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Font", value = SubtitleFontManager.getCurrentFontLabel(ctx),
                adjustable = true, onAdjust = { d ->
                    if (d > 0) SubtitleFontManager.cycleFontUp(ctx) else SubtitleFontManager.cycleFontDown(ctx); onChanged.run()
                }),
            UnifiedMenuController.Row("Bold", value = if (SubtitleSettings.getBold(ctx)) "On" else "Off",
                adjustable = true, onAdjust = { _ ->
                    SubtitleSettings.setBold(ctx, !SubtitleSettings.getBold(ctx)); onChanged.run()
                }),
            UnifiedMenuController.Row("Reset all to defaults", accent = true, onOk = {
                SubtitleSettings.resetToDefaults(ctx); SubtitleFontManager.resetToDefault(ctx); onChanged.run()
            })
        )
    }
}
