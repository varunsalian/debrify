package com.debrify.app.tv

import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistTicketSkinCharacterizationTest : TvPlaylistSkinContracts() {
    override val skin = TvControlsSkin.TICKET
}
