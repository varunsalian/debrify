package com.debrify.app.recording

import android.content.Context
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Which captures may write to the share, read as the legacy (single) profile. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class SmbRecordingOutputTest {
	private val context: Context = RuntimeEnvironment.getApplication()
	private val owner = "legacy-admin-v1"

	private fun store(target: String?, password: String? = null) {
		context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().apply {
			clear()
			target?.let { putString("flutter.recording_smb_target_v1", it) }
			password?.let { putString("flutter.recording_smb_password_v1", it) }
			putString("flutter.vault_key_source_v1", "pepper")
		}.commit()
	}

	@Before
	fun reset() = store(null)

	@Test
	fun aCompleteEnabledTargetIsUsedWithItsFolderAndLogin() {
		store(
			"""{"enabled":true,"host":" nas ","share":"media","folder":"TV\\Rec/ . /x",""" +
				""""user":"me","domain":"HOME","recordDirect":true}""",
			// Sealed with the pepper-only key (see SecretVaultReaderTest).
			"enc1:d5d9SmpaHEmHhzwBzRVk9E/6ki1aHBBrUw8srt8DnK504yXkqTr7nOBk",
		)
		val target = SmbRecordingOutput.targetFor(context, owner)!!
		assertEquals("nas", target.host)
		assertEquals(listOf("TV", "Rec", "x"), target.folder)
		assertEquals("me", target.user)
		assertEquals("HOME", target.domain)
		assertEquals("nas-pässword!", target.password)
		assertEquals("\\\\nas\\media\\TV\\Rec\\x", target.displayAddress)
	}

	@Test
	fun targetsSavedBeforeTheOptionRecordDirect() {
		store("""{"enabled":true,"host":"nas","share":"media"}""")
		assertEquals("media", SmbRecordingOutput.targetFor(context, owner)?.share)
	}

	@Test
	fun offIncompleteOrSomeoneElsesCaptureRecordsLocally() {
		store("""{"enabled":true,"host":"nas","share":"media","recordDirect":false}""")
		assertNull(SmbRecordingOutput.targetFor(context, owner))
		store("""{"enabled":false,"host":"nas","share":"media"}""")
		assertNull(SmbRecordingOutput.targetFor(context, owner))
		store("""{"enabled":true,"host":"nas","share":"a/b"}""")
		assertNull(SmbRecordingOutput.targetFor(context, owner))
		store("""{"enabled":true,"host":"nas","share":"media"}""")
		assertNull(SmbRecordingOutput.targetFor(context, "another-profile"))
	}

	@Test
	fun anUnreadablePasswordNeverLogsOnWithAWrongOne() {
		store("""{"enabled":true,"host":"nas","share":"media","user":"me"}""", "enc1:AAAA" + "A".repeat(60))
		assertNull(SmbRecordingOutput.targetFor(context, owner))
	}

	@Test
	fun shareUrisAreRecognisedAndLabelled() {
		val uri = Uri.parse("smb://nas/media/TV/News.ts")
		assertTrue(SmbRecordingOutput.isShare(uri))
		assertFalse(SmbRecordingOutput.isShare(Uri.parse("content://media/external/downloads/1")))
		assertEquals("\\\\nas\\media\\TV\\News.ts", SmbRecordingOutput.label(uri))
	}
}
