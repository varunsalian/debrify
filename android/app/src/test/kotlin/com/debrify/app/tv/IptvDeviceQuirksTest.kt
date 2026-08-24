package com.debrify.app.tv

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IptvDeviceQuirksTest {
    @Test
    fun googleTvStreamerUsesStrictTsFromFirstTune() {
        assertTrue(
            IptvDeviceQuirks.startsIptvWithStrictTs(
                manufacturer = "Google",
                model = "Google TV Streamer",
                device = "kirkwood",
            ),
        )
    }

    @Test
    fun kirkwoodCodenameSurvivesVariantModelStrings() {
        assertTrue(
            IptvDeviceQuirks.startsIptvWithStrictTs(
                manufacturer = "Google",
                model = "GTV Streamer 4K",
                device = " KIRKWOOD ",
            ),
        )
    }

    @Test
    fun publicModelNameSurvivesMissingCodenameAndCase() {
        assertTrue(
            IptvDeviceQuirks.startsIptvWithStrictTs(
                manufacturer = " google ",
                model = "GOOGLE TV STREAMER (4K)",
                device = null,
            ),
        )
    }

    @Test
    fun otherAndroidTvDevicesKeepAggressiveTsJoin() {
        assertFalse(
            IptvDeviceQuirks.startsIptvWithStrictTs(
                manufacturer = "Xiaomi",
                model = "Mi Box S",
                device = "oneday",
            ),
        )
        assertFalse(
            IptvDeviceQuirks.startsIptvWithStrictTs(
                manufacturer = "Google",
                model = "Chromecast",
                device = "sabrina",
            ),
        )
    }
}
