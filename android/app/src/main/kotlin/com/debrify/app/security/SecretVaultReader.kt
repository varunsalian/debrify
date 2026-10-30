package com.debrify.app.security

import android.content.Context
import android.provider.Settings
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Native reader for values sealed by Dart's SecretVault
 * (lib/services/secret_vault.dart): `enc1:` + base64(nonce(12) ∥ ciphertext
 * ∥ tag(16)), AES-GCM-256 under HKDF-SHA256(pepper ∥ device id). Used where a
 * credential is needed with no Flutter running (a scheduled recording that
 * writes to an SMB share). The constants and the key-source rules mirror the
 * Dart side exactly; change both together.
 */
object SecretVaultReader {
	private const val PREFIX = "enc1:"
	private const val NONCE_LENGTH = 12
	private const val TAG_LENGTH = 16
	private const val KEY_SOURCE_PREF = "flutter.vault_key_source_v1"
	private val INFO = "debrify-secret-vault-v1".toByteArray(Charsets.UTF_8)

	private val PEPPER = ints(
		3, 199, 32, 163, 35, 25, 9, 245,
		14, 252, 204, 172, 74, 64, 180, 94,
		230, 248, 87, 4, 175, 59, 151, 150,
		220, 197, 5, 82, 68, 33, 150, 113,
	)
	private val SALT = ints(
		19, 126, 161, 133, 65, 154, 196, 229,
		237, 165, 172, 17, 159, 44, 23, 89,
		3, 97, 230, 120, 123, 166, 77, 99,
		32, 16, 242, 6, 138, 236, 242, 239,
	)

	private fun ints(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

	/**
	 * Like Dart's `SecretVault.open`: null stays null, a sealed value is
	 * decrypted (any failure gives null), anything else is legacy plaintext.
	 */
	fun open(context: Context, stored: String?): String? {
		if (stored == null) return null
		if (!stored.startsWith(PREFIX)) return stored
		return try {
			val packed = Base64.decode(stored.substring(PREFIX.length), Base64.DEFAULT)
			if (packed.size < NONCE_LENGTH + TAG_LENGTH) return null
			val key = key(context) ?: return null
			val cipher = Cipher.getInstance("AES/GCM/NoPadding")
			cipher.init(
				Cipher.DECRYPT_MODE,
				SecretKeySpec(key, "AES"),
				GCMParameterSpec(TAG_LENGTH * 8, packed, 0, NONCE_LENGTH),
			)
			// Java's GCM takes ciphertext ∥ tag, which is the envelope's tail.
			String(cipher.doFinal(packed, NONCE_LENGTH, packed.size - NONCE_LENGTH), Charsets.UTF_8)
		} catch (_: Exception) {
			null
		}
	}

	/**
	 * The install's committed key source (Dart writes it on first use):
	 * `pepper` derives from the pepper alone, `id:<hash>` adds ANDROID_ID.
	 * No marker means nothing was ever sealed.
	 */
	private fun key(context: Context): ByteArray? {
		val marker = context
			.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
			.getString(KEY_SOURCE_PREF, null)
			?: return null
		val deviceId = when {
			marker == "pepper" -> ""
			marker.startsWith("id:") ->
				Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
					?: return null
			else -> return null
		}
		return hkdf(PEPPER + deviceId.toByteArray(Charsets.UTF_8))
	}

	/** RFC 5869 HKDF-SHA256 with [SALT] and [INFO]; one 32-byte block. */
	private fun hkdf(ikm: ByteArray): ByteArray {
		val extract = Mac.getInstance("HmacSHA256")
		extract.init(SecretKeySpec(SALT, "HmacSHA256"))
		val prk = extract.doFinal(ikm)
		val expand = Mac.getInstance("HmacSHA256")
		expand.init(SecretKeySpec(prk, "HmacSHA256"))
		expand.update(INFO)
		expand.update(1.toByte())
		return expand.doFinal()
	}
}
