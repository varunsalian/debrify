package com.debrify.app.profiles

import android.content.Context
import android.content.Intent
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity
import com.debrify.app.tv.TorboxTvPlayerActivity
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NativePlayerRejectedLaunchTest {
    @Before fun rejectSettings() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit().clear().putString("flutter.profiles_runtime_mode_v1", "profileCommitted").commit()
        ProfilePrivacyState.update(context, false, false)
    }

    @Test fun torrentPlayerCanFinishBeforeItsViewsAreBound() {
        val controller = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java, Intent())
            .create()
        assertTrue(controller.get().isFinishing)
        controller.start().resume().pause().stop().destroy()
    }

    @Test fun debrifyTvPlayerCanFinishBeforeItsViewsAreBound() {
        val controller = Robolectric.buildActivity(TorboxTvPlayerActivity::class.java, Intent())
            .create()
        assertTrue(controller.get().isFinishing)
        controller.start().resume().pause().stop().destroy()
    }
}
