package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistLifecycleCharacterizationTest : TvPhase13OriginalTest() {
    @Test fun destroyPreservesSevenStatementOrderAndClearsOwnedReferencesBeforeFinished() {
        assertEquals(listOf("playlistAdapter","seriesPlaylistAdapter","moviePlaylistAdapter","focusRecoveryHandler.remove","focusRecoveryRunnable","seasonTabs.clear","movieTabs.clear"),TvPlaylistBytecodeAccess.teardown(activity.javaClass))
        var fired=0;val r=Runnable{fired++};set("focusRecoveryRunnable",r);handler().postDelayed(r,100)
        messenger.onSend={if(it.call.method=="torrentPlaybackFinished") {
            assertNull(field("playlistAdapter"));assertNull(field("seriesPlaylistAdapter"));assertNull(field("moviePlaylistAdapter"));assertNull(field("focusRecoveryRunnable"))
            assertTrue(seasonTabs().isEmpty());assertTrue(movieTabs().isEmpty());assertNull(playlist().adapter)
        }}
        destroyNow();advanceUi(100)
        assertEquals(0,fired);assertNull(field("playlistAdapter"));assertNull(field("seriesPlaylistAdapter"));assertNull(field("moviePlaylistAdapter"));assertNull(field("focusRecoveryRunnable"));assertTrue(seasonTabs().isEmpty());assertTrue(movieTabs().isEmpty());assertNull(playlist().adapter)
        assertEquals(1,requests("torrentPlaybackFinished").size)
    }
}
