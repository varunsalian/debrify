package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvFormattingCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun playbackTimeFloorsSecondsAndCrossesHourBoundary() {
        val locale = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            for ((ms, expected) in listOf(-1L to "00:00", 0L to "00:00", 999L to "00:00", 1000L to "00:01",
                59_999L to "00:59", 60_000L to "01:00", 3_599_999L to "59:59", 3_600_000L to "1:00:00",
                3_661_000L to "1:01:01", 360_000_000L to "100:00:00")) assertEquals(expected, call("formatTime", arrayOf(longType), ms))
        } finally { Locale.setDefault(locale) }
    }

    @Test fun spelledNumbersKeepNullDigitsTensHyphensAndFiftyBoundary() {
        val cases = listOf(null to "", -1 to "-1", 0 to "Zero", 1 to "One", 7 to "Seven", 19 to "Nineteen",
            20 to "Twenty", 21 to "Twenty-One", 29 to "Twenty-Nine", 30 to "Thirty", 39 to "Thirty-Nine",
            40 to "Forty", 49 to "Forty-Nine", 50 to "50")
        for ((n, expected) in cases) assertEquals(expected, call("spellNumber", arrayOf(boxedIntType), n))
    }

    @Test fun seekAccelerationKeepsBaseNegativeRepeatsAndInclusiveCap() {
        for ((repeat, expected) in listOf(-1 to 8000L, 0 to 10_000L, 1 to 12_000L, 54 to 118_000L, 55 to 120_000L, 56 to 120_000L)) {
            assertEquals(expected, call("getAcceleratedSeekStep", arrayOf(intType), repeat))
        }
    }

    @Test fun menuRowPassesValuesAndCallbacksAndUsesRealDefaultDispatch() {
        val types = arrayOf(stringType, stringType, boolType, boolType, boolType, boxedIntType, boolType, stringType,
            kotlin.jvm.functions.Function0::class.java, kotlin.jvm.functions.Function1::class.java)
        var ok = 0; var adjusted = 0
        val onOk: () -> Unit = { ok++ }; val onAdjust: (Int) -> Unit = { adjusted = it }
        val row = call("mrow", types, "Title", "Value", true, true, false, 0x123456, true, "tag", onOk, onAdjust) as UnifiedMenuController.Row
        assertEquals(UnifiedMenuController.Row("Title", "Value", true, true, false, 0x123456, true, "tag", onOk, onAdjust), row)
        assertSame(onOk, row.onOk); assertSame(onAdjust, row.onAdjust)
        row.onOk!!(); row.onAdjust!!(-1); assertEquals(1, ok); assertEquals(-1, adjusted)
        val defaults = defaultCall("mrow", types, 1022, "Default", null, false, false, false, null, false, null, null, null)
        assertEquals(UnifiedMenuController.Row("Default"), defaults)
    }
}
