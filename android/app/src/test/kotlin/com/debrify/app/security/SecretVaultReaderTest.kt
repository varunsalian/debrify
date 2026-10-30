package com.debrify.app.security

import android.content.Context
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Values sealed by Dart's SecretVault (generated with SecretVault.seal and a
 * pinned device id), opened natively. If these fail, the two sides' key
 * derivation has drifted apart.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class SecretVaultReaderTest {
	private val context: Context = RuntimeEnvironment.getApplication()
	private val password = "nas-pässword!"

	private fun marker(value: String?) {
		context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
			.edit().apply {
				if (value == null) remove("flutter.vault_key_source_v1")
				else putString("flutter.vault_key_source_v1", value)
			}.commit()
	}

	@Test
	fun opensAValueSealedUnderTheDeviceId() {
		Settings.Secure.putString(context.contentResolver, Settings.Secure.ANDROID_ID, "a1b2c3d4e5f60718")
		marker("id:uC78RsBz2dj239Ctc4pwdA==")
		assertEquals(
			password,
			SecretVaultReader.open(context, "enc1:Cyif/NWdev+dYLz7oaysT7YRUQwNJnnANOERVyghjFrwCkGcHrQ97xrx"),
		)
	}

	@Test
	fun opensAValueSealedWithThePepperOnly() {
		marker("pepper")
		assertEquals(
			password,
			SecretVaultReader.open(context, "enc1:d5d9SmpaHEmHhzwBzRVk9E/6ki1aHBBrUw8srt8DnK504yXkqTr7nOBk"),
		)
	}

	@Test
	fun aWrongKeyOrNoKeySourceReadsAsAbsent() {
		Settings.Secure.putString(context.contentResolver, Settings.Secure.ANDROID_ID, "another-device")
		marker("id:uC78RsBz2dj239Ctc4pwdA==")
		assertNull(SecretVaultReader.open(context, "enc1:Cyif/NWdev+dYLz7oaysT7YRUQwNJnnANOERVyghjFrwCkGcHrQ97xrx"))
		marker(null)
		assertNull(SecretVaultReader.open(context, "enc1:d5d9SmpaHEmHhzwBzRVk9E/6ki1aHBBrUw8srt8DnK504yXkqTr7nOBk"))
	}

	@Test
	fun legacyPlaintextAndNullPassThroughLikeDart() {
		assertNull(SecretVaultReader.open(context, null))
		assertEquals("plain", SecretVaultReader.open(context, "plain"))
	}
}
