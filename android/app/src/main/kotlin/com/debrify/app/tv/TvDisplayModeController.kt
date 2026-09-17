package com.debrify.app.tv

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.Display
import androidx.media3.common.Format
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

internal enum class TvContentDisplayMatchMode(val storageKey: String) {
    SYSTEM("system"),
    OFF("off"),
    FRAME_RATE("frame_rate"),
    FRAME_RATE_AND_RESOLUTION("frame_rate_resolution");

    val requestsMatching: Boolean
        get() = this == FRAME_RATE || this == FRAME_RATE_AND_RESOLUTION

    companion object {
        fun fromStorage(value: String?): TvContentDisplayMatchMode =
            entries.firstOrNull { it.storageKey == value } ?: SYSTEM
    }
}

internal data class TvDisplayModeCandidate(
    val id: Int,
    val width: Int,
    val height: Int,
    val refreshRate: Float,
)

/** Pure mode-selection policy, kept Android-free so it can be unit tested. */
internal object TvDisplayModeSelector {
    private const val MAX_CADENCE_ERROR_HZ = 0.20

    fun select(
        baseMode: TvDisplayModeCandidate,
        supportedModes: List<TvDisplayModeCandidate>,
        videoWidth: Int,
        videoHeight: Int,
        videoFrameRate: Float,
        matchResolution: Boolean,
    ): TvDisplayModeCandidate? {
        if (videoWidth <= 0 || videoHeight <= 0 ||
            !videoFrameRate.isFinite() || videoFrameRate <= 0f
        ) return null

        val candidates = if (matchResolution) {
            supportedModes
        } else {
            supportedModes.filter {
                it.width == baseMode.width && it.height == baseMode.height
            }
        }

        return candidates
            .mapNotNull { mode ->
                val cadence = cadenceScore(mode.refreshRate, videoFrameRate)
                    ?: return@mapNotNull null
                val resolution = if (matchResolution) {
                    resolutionScore(mode, videoWidth, videoHeight)
                } else {
                    0.0
                }
                ScoredMode(mode, resolution, cadence.first, cadence.second)
            }
            .minWithOrNull(
                compareBy<ScoredMode> { it.resolutionScore }
                    .thenBy { it.cadenceError }
                    .thenBy { it.cadenceMultiple }
                    .thenBy { abs(it.mode.refreshRate - baseMode.refreshRate) },
            )
            ?.mode
    }

    /**
     * Accept exact rates and integer multiples (23.976/47.952/71.928,
     * 25/50/100, 29.97/59.94, etc.). A small tolerance covers TVs that expose
     * 23.98 or 59.95 rather than the exact rational value.
     */
    private fun cadenceScore(displayHz: Float, contentFps: Float): Pair<Double, Int>? {
        if (!displayHz.isFinite() || displayHz <= 0f) return null
        val multiple = (displayHz / contentFps).roundToInt().coerceIn(1, 5)
        val error = abs(displayHz - contentFps * multiple).toDouble()
        return if (error <= MAX_CADENCE_ERROR_HZ) error to multiple else null
    }

    /**
     * Width is the strongest signal because cinema files commonly retain a
     * standard 1920/3840 raster width while cropping letterbox rows. Prefer a
     * mode that can contain the decoded frame, then the closest dimensions.
     */
    private fun resolutionScore(
        mode: TvDisplayModeCandidate,
        videoWidth: Int,
        videoHeight: Int,
    ): Double {
        val widthDelta = abs(mode.width - videoWidth).toDouble() / max(videoWidth, 1)
        val heightDelta = abs(mode.height - videoHeight).toDouble() / max(videoHeight, 1)
        val undersizedPenalty =
            (if (mode.width < videoWidth) 8.0 else 0.0) +
                (if (mode.height < videoHeight) 4.0 else 0.0)
        return undersizedPenalty + widthDelta * 4.0 + heightDelta
    }

    private data class ScoredMode(
        val mode: TvDisplayModeCandidate,
        val resolutionScore: Double,
        val cadenceError: Double,
        val cadenceMultiple: Int,
    )
}

/**
 * Owns WindowManager's preferred display mode for one playback Activity.
 * Clearing the preference on teardown returns mode choice to the system.
 */
internal class TvDisplayModeController(
    private val activity: Activity,
    val matchMode: TvContentDisplayMatchMode,
) {
    private val display: Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        activity.display
    } else {
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay
    }
    private val baseMode: TvDisplayModeCandidate? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            display?.mode?.toCandidate()
        } else {
            null
        }
    @Volatile
    private var preferredModeId = 0

    fun onVideoFormat(format: Format?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || !matchMode.requestsMatching) return
        val base = baseMode ?: return
        val frameRate = format?.frameRate ?: Format.NO_VALUE.toFloat()
        var width = format?.width ?: Format.NO_VALUE
        var height = format?.height ?: Format.NO_VALUE
        if (format?.rotationDegrees == 90 || format?.rotationDegrees == 270) {
            val swap = width
            width = height
            height = swap
        }
        val modes = display?.supportedModes?.map { it.toCandidate() }.orEmpty()
        val selected = TvDisplayModeSelector.select(
            baseMode = base,
            supportedModes = modes,
            videoWidth = width,
            videoHeight = height,
            videoFrameRate = frameRate,
            matchResolution = matchMode == TvContentDisplayMatchMode.FRAME_RATE_AND_RESOLUTION,
        )
        if (selected == null) {
            // This Activity can outlive many episodes, channels, and source
            // switches. Never let the previous item's explicit mode survive
            // when the new format is incomplete or has no compatible output.
            clear()
            return
        }
        if (selected.id == preferredModeId) return
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed) return@runOnUiThread
            val attributes = activity.window.attributes
            attributes.preferredDisplayModeId = selected.id
            activity.window.attributes = attributes
            preferredModeId = selected.id
            Log.i(
                "DebrifyDisplayMatch",
                String.format(
                    Locale.US,
                    "requested=%dx%d@%.3f content=%dx%d@%.3f mode=%s",
                    selected.width,
                    selected.height,
                    selected.refreshRate,
                    width,
                    height,
                    frameRate,
                    matchMode.storageKey,
                ),
            )
        }
    }

    fun clear() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        // Publish the reset before posting it to the window. If a valid format
        // arrives immediately after an invalid transition, it must enqueue a
        // fresh apply even when it selects the same mode as the outgoing item.
        preferredModeId = 0
        activity.runOnUiThread {
            val attributes = activity.window.attributes
            if (attributes.preferredDisplayModeId != 0) {
                attributes.preferredDisplayModeId = 0
                activity.window.attributes = attributes
            }
        }
    }

    private fun Display.Mode.toCandidate() = TvDisplayModeCandidate(
        id = modeId,
        width = physicalWidth,
        height = physicalHeight,
        refreshRate = refreshRate,
    )
}
