package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowBuild

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvDeviceCharacterizationTest : TvPhase17OriginalTest() {
    private fun device(manufacturer: String,model: String,device: String) {
        ShadowBuild.setManufacturer(manufacturer);ShadowBuild.setModel(model);ShadowBuild.setDevice(device)
    }
    private fun strictNote() = org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("demux=strict reason=device-quirk")}
    @Test fun kirkwoodStartsStrictAtFirstTune() { device("other","Other","kirkwood");tune();assertTrue(field("iptvStrictTsActive") as Boolean);assertTrue(strictNote()) }
    @Test fun googleStreamerStartsStrictAtFirstTune() { device(" Google ","Google TV Streamer 4K","other");tune();assertTrue(field("iptvStrictTsActive") as Boolean);assertTrue(strictNote()) }
    @Test fun ordinaryDeviceStaysAggressiveAndLaterBuildChangesDoNotReevaluateTheLazy() {
        device("Other","Google TV Streamer","other");tune();assertFalse(field("iptvStrictTsActive") as Boolean);assertFalse(strictNote())
        device("Google","Google TV Streamer","kirkwood");tune();assertFalse(field("iptvStrictTsActive") as Boolean);assertFalse(strictNote())
    }
    @Test fun quirkIsDeferredUntilTheFirstTuneAndThenFixedForTheSession() {
        val deferred=field("iptvStartsWithStrictTs\$delegate") as Lazy<*>;assertFalse(deferred.isInitialized())
        device("Other","Other","kirkwood");tune();assertTrue(deferred.isInitialized());assertTrue(field("iptvStrictTsActive") as Boolean)
        device("Other","Other","other");tune();assertTrue(field("iptvStrictTsActive") as Boolean)
    }
}
