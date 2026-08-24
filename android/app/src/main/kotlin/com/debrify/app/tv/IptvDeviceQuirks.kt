package com.debrify.app.tv

/** Device-specific IPTV workarounds kept outside the player activity so the
 * matching rules can be covered by plain JVM tests. */
internal object IptvDeviceQuirks {
    /**
     * The Google TV Streamer's MediaTek decoder can accept a progressive TS
     * stream joined on a non-IDR frame without ever rendering video, while
     * audio continues normally. The browse preview works because it uses the
     * stock (IDR-only) TS extractor. Start the fullscreen player on that same
     * strict path instead of waiting for the video-stall recovery ladder to
     * discover the quirk after visible freezes and re-tunes.
     *
     * Match the public model name and the firmware device codename. Either is
     * sufficient because OEM/region builds have not always exposed identical
     * display strings.
     */
    fun startsIptvWithStrictTs(
        manufacturer: String?,
        model: String?,
        device: String?,
    ): Boolean {
        val normalizedManufacturer = manufacturer.normalized()
        val normalizedModel = model.normalized()
        val normalizedDevice = device.normalized()

        return normalizedDevice == "kirkwood" ||
            (normalizedManufacturer == "google" &&
                normalizedModel.contains("google tv streamer"))
    }

    private fun String?.normalized(): String = orEmpty().trim().lowercase()
}
