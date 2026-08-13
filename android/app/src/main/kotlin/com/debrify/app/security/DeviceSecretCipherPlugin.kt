package com.debrify.app.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore-backed AEAD for profile resource and job secrets. The key
 * is non-exportable and the channel never returns it to Dart.
 */
object DeviceSecretCipherPlugin {
    private const val CHANNEL = "debrify/device_secret"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "debrify.profile.device-secret.v1"
    private const val ENVELOPE_VERSION: Byte = 1
    private const val IV_BYTES = 12

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initialize" -> {
                            getOrCreateKey()
                            result.success(true)
                        }
                        "seal" -> {
                            val plaintext = decodeArgument(call.argument("plaintext"))
                            val aad = decodeArgument(call.argument("associatedData"))
                            result.success(sealForNative(plaintext, aad))
                        }
                        "open" -> {
                            val envelope = call.argument<String>("envelope")
                                ?: error("Missing channel argument")
                            val aad = decodeArgument(call.argument("associatedData"))
                            result.success(
                                Base64.encodeToString(openForNative(envelope, aad), Base64.NO_WRAP),
                            )
                        }
                        "destroy" -> {
                            KeyStore.getInstance(KEYSTORE).apply { load(null) }
                                .deleteEntry(KEY_ALIAS)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("device_secret_failed", error.message, null)
                }
            }
    }

    @JvmStatic
    fun sealForNative(plaintext: ByteArray, aad: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext)
        val packed = byteArrayOf(ENVELOPE_VERSION) + cipher.iv + ciphertext
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    @JvmStatic
    fun openForNative(envelope: String, aad: ByteArray): ByteArray {
        val packed = Base64.decode(envelope, Base64.NO_WRAP)
        require(packed.size > 1 + IV_BYTES + 16 && packed[0] == ENVELOPE_VERSION) {
            "Unsupported or corrupt secret envelope"
        }
        val iv = packed.copyOfRange(1, 1 + IV_BYTES)
        val ciphertext = packed.copyOfRange(1 + IV_BYTES, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(128, iv),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(ciphertext)
    }

	@Synchronized
	private fun getOrCreateKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private fun decodeArgument(value: String?): ByteArray {
        require(!value.isNullOrEmpty()) { "Missing channel argument" }
        return Base64.decode(value, Base64.NO_WRAP)
    }
}
