package com.debrify.app.recording

import android.content.Context
import org.robolectric.RuntimeEnvironment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class RecordingOutputPrefsTest {
	private val minute = 60_000L

	@Test
	fun missingOrBrokenSettingKeepsTodaysBehaviour() {
		for (raw in listOf(null, "", "not json", "[]")) {
			val prefs = RecordingOutputPrefs.parse(raw)
			assertNull(prefs.treeUri)
			assertEquals(0L, prefs.startPadMs)
			assertEquals(2 * minute, prefs.endPadMs)
		}
	}

	@Test
	fun explicitValuesAreReadAndClamped() {
		val prefs = RecordingOutputPrefs.parse(
			"""{"treeUri":" content://tree/usb ","startPadMinutes":5,"endPadMinutes":99}""",
		)
		assertEquals("content://tree/usb", prefs.treeUri)
		assertEquals(5 * minute, prefs.startPadMs)
		assertEquals(15 * minute, prefs.endPadMs)
		assertEquals(0L, RecordingOutputPrefs.parse("""{"startPadMinutes":-3}""").startPadMs)
	}

	@Test
	fun explicitZeroEndPadTurnsTheDefaultOff() {
		val prefs = RecordingOutputPrefs.parse("""{"endPadMinutes":0}""")
		assertEquals(0L, prefs.endPadMs)
		assertNull(RecordingOutputPrefs.parse("""{"treeUri":""}""").treeUri)
	}

	@Test
	fun readsTheDeviceSettingDartWrites() {
		val context: Context = RuntimeEnvironment.getApplication()
		context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
			.edit()
			.putString(
				"flutter.${RecordingOutputPrefs.KEY}",
				"""{"startPadMinutes":1,"endPadMinutes":3}""",
			)
			.commit()
		val prefs = RecordingOutputPrefs.read(context)
		assertEquals(1 * minute, prefs.startPadMs)
		assertEquals(3 * minute, prefs.endPadMs)
	}
}
