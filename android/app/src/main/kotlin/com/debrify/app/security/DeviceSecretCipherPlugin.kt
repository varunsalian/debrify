package com.debrify.app.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.AEADBadTagException
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
    private const val STATE_PREFERENCES = "debrify_device_secret_state"
    private const val CANARY_KEY = "canary_v1"
    private const val RESET_TOKEN_KEY = "unopenable_reset_token_v1"
    private const val ENVELOPE_VERSION: Byte = 1
    private const val IV_BYTES = 12
    private val CANARY_PLAINTEXT = "debrify-device-secret-canary-v1".toByteArray(Charsets.UTF_8)
    private val CANARY_AAD = "debrify-device-secret-canary-aad-v1".toByteArray(Charsets.UTF_8)
    @Volatile private var migrationAuditPending = false
    @Volatile private var resetAuthorizationAvailable = false
    @Volatile private var diagnosticContext: Context? = null
    private var lastFailureDiagnosticMs: Long? = null

    fun register(context: Context, engine: FlutterEngine) {
        val applicationContext = context.applicationContext
        diagnosticContext = applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initialize" -> {
                            val allowCreate = call.argument<Boolean>("allowCreate") ?: true
                            val auditRequired = initializeKey(applicationContext, allowCreate)
                            migrationAuditPending = auditRequired
                            resetAuthorizationAvailable = false
                            clearResetAuthorization(applicationContext)
                            result.success(if (auditRequired) "migration_audit_required" else "ready")
                        }
                        "commitMigrationAudit" -> {
                            commitCanary(applicationContext)
                            migrationAuditPending = false
                            resetAuthorizationAvailable = false
                            clearResetAuthorization(applicationContext)
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
                            destroy(applicationContext)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    if (call.method == "initialize" &&
                        (error is DeviceSecretMissingException || error is DeviceSecretUnreadableException)
                    ) {
                        resetAuthorizationAvailable = true
                    }
                    if (call.method == "open" && migrationAuditPending) {
                        resetAuthorizationAvailable = true
                    }
                    if (call.method == "commitMigrationAudit" &&
                        error is DeviceSecretUnreadableException
                    ) {
                        resetAuthorizationAvailable = true
                    }
                    result.error(
                        errorCode(error),
                        diagnosticDescription(call.method, error),
                        null,
                    )
                }
            }
    }

    @JvmStatic
    fun sealForNative(plaintext: ByteArray, aad: ByteArray): String {
        return sealWithKey(plaintext, aad, getRequiredKey())
    }

    private fun sealWithKey(plaintext: ByteArray, aad: ByteArray, key: SecretKey): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext)
        val packed = byteArrayOf(ENVELOPE_VERSION) + cipher.iv + ciphertext
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    @JvmStatic
    fun openForNative(envelope: String, aad: ByteArray): ByteArray {
        try {
            return openWithKey(envelope, aad, getRequiredKey())
        } catch (error: Exception) {
            diagnoseOpenFailure(error)
            if (error is AEADBadTagException && storedCanaryIsReadable()) {
                throw DeviceSecretRecordUnreadableException(error)
            }
            throw error
        }
    }

    // Only isolate a record after proving the persisted key still works.
    // Missing/pre-canary vaults and provider outages retain global recovery.
    private fun storedCanaryIsReadable(): Boolean = try {
        val context = diagnosticContext
        val canary = context?.getSharedPreferences(STATE_PREFERENCES, Context.MODE_PRIVATE)
            ?.getString(CANARY_KEY, null)
        if (canary == null) false else {
            verifyCanary(canary, getRequiredKey())
            true
        }
    } catch (_: Exception) {
        false
    }

    // Read-only with respect to persisted vault state. Never replace a key or
    // rewrite an envelope while diagnosing an authentication failure.
    @Synchronized
    private fun diagnoseOpenFailure(original: Exception) {
        val now = SystemClock.elapsedRealtime()
        val previous = lastFailureDiagnosticMs
        if (previous != null && now - previous < 30_000) return
        lastFailureDiagnosticMs = now
        try {
            val context = diagnosticContext ?: return
            val key = getRequiredKey()
            val canary = context.getSharedPreferences(STATE_PREFERENCES, Context.MODE_PRIVATE)
                .getString(CANARY_KEY, null)
            fun check(block: () -> Unit): String = try {
                block()
                "ok"
            } catch (error: Exception) {
                diagnosticDescription("check", error)
            }
            val stored = if (canary == null) "absent" else check {
                verifyCanary(canary, key)
            }
            val fresh = check {
                val probe = sealWithKey(CANARY_PLAINTEXT, CANARY_AAD, key)
                // Reload the alias rather than only testing the first handle.
                verifyCanary(probe, getRequiredKey())
            }
            Log.w("DebrifyDeviceVault", "event=open_failure " +
                "error=${diagnosticDescription("open", original)} " +
                "stored_canary=$stored fresh_roundtrip=$fresh")
        } catch (error: Exception) {
            Log.w("DebrifyDeviceVault", "event=diagnostic_unavailable " +
                "error=${diagnosticDescription("open", original)} " +
                "probe=${diagnosticDescription("probe", error)}")
        }
    }

    private fun openWithKey(envelope: String, aad: ByteArray, key: SecretKey): ByteArray {
        val packed = Base64.decode(envelope, Base64.NO_WRAP)
        require(packed.size > 1 + IV_BYTES + 16 && packed[0] == ENVELOPE_VERSION) {
            "Unsupported or corrupt secret envelope"
        }
        val iv = packed.copyOfRange(1, 1 + IV_BYTES)
        val ciphertext = packed.copyOfRange(1 + IV_BYTES, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(128, iv),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(ciphertext)
    }

    /**
     * Establishes and proves the device key before Dart is allowed to mount
     * profile state. A committed/interrupted registry passes allowCreate=false:
     * losing its key must enter recovery, never mint a replacement that makes
     * every existing envelope look corrupt.
     */
    @Synchronized
    private fun initializeKey(context: Context, allowCreate: Boolean): Boolean {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        val preferences = context.getSharedPreferences(STATE_PREFERENCES, Context.MODE_PRIVATE)
        val storedCanary = preferences.getString(CANARY_KEY, null)
        var key = loadExistingKey(store)
        var createdKey = false
        if (key == null) {
            if (!allowCreate || storedCanary != null) {
                throw DeviceSecretMissingException()
            }
            key = generateCompatibleKey(store)
            createdKey = true
        }

        if (storedCanary == null) {
            if (!allowCreate) {
                // A pre-canary installation with profile state must prove this
                // alias against an existing encrypted resource in Dart. A
                // self-generated canary alone cannot distinguish the original
                // key from one silently replaced by an older app build.
                return true
            }
            // Upgrade healthy pre-canary installs in place. Verify before
            // persisting so a provider with incompatible GCM IV behaviour
            // cannot leave behind a permanently unreadable marker.
            persistCanary(
                preferences,
                key,
                classifyCipherFailure = !createdKey,
            )
        } else {
            verifyCanary(storedCanary, key)
        }
        return false
    }

    @Synchronized
    private fun commitCanary(context: Context) {
        val preferences = context.getSharedPreferences(STATE_PREFERENCES, Context.MODE_PRIVATE)
        val key = getRequiredKey()
        val storedCanary = preferences.getString(CANARY_KEY, null)
        if (storedCanary == null) {
            persistCanary(preferences, key, classifyCipherFailure = true)
        }
        else verifyCanary(storedCanary, key)
    }

    private fun persistCanary(
        preferences: android.content.SharedPreferences,
        key: SecretKey,
        classifyCipherFailure: Boolean,
    ) {
        val candidate = try {
            probeKey(key)
        } catch (error: Throwable) {
            if (classifyCipherFailure) throw DeviceSecretUnreadableException(error)
            throw error
        }
        if (!preferences.edit().putString(CANARY_KEY, candidate).commit()) {
            throw IllegalStateException("Could not persist device-secret canary")
        }
    }

    private fun verifyCanary(envelope: String, key: SecretKey) {
        try {
            val opened = openWithKey(envelope, CANARY_AAD, key)
            if (!MessageDigest.isEqual(opened, CANARY_PLAINTEXT)) {
                throw DeviceSecretUnreadableException()
            }
        } catch (error: DeviceSecretUnreadableException) {
            throw error
        } catch (error: Throwable) {
            throw DeviceSecretUnreadableException(error)
        }
    }

    /**
     * Some older Fire OS providers accept 256-bit key generation but reject
     * the first AES-GCM operation. Exercise the exact seal/open path before
     * accepting a size, while replacement is still safe for a fresh vault.
     */
    private fun generateCompatibleKey(store: KeyStore): SecretKey {
        var firstFailure: Throwable? = null
        for (keySize in intArrayOf(256, 128)) {
            try {
                val key = generateKey(keySize)
                probeKey(key)
                return key
            } catch (error: Throwable) {
                if (firstFailure == null) firstFailure = error
                // Creation is permitted only when Dart proved there is no
                // profile registry. Remove a partially-created fresh alias
                // before the compatibility retry.
                store.deleteEntry(KEY_ALIAS)
            }
        }
        val failure = IllegalStateException("Android Keystore AES-GCM key generation failed")
        firstFailure?.let(failure::initCause)
        throw failure
    }

    private fun probeKey(key: SecretKey): String {
        val candidate = sealWithKey(CANARY_PLAINTEXT, CANARY_AAD, key)
        verifyCanary(candidate, key)
        return candidate
    }

    private fun generateKey(keySize: Int): SecretKey {
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(keySize)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    @Synchronized
    private fun getRequiredKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return loadExistingKey(store) ?: throw DeviceSecretMissingException()
    }

    private fun loadExistingKey(store: KeyStore): SecretKey? {
        if (!store.containsAlias(KEY_ALIAS)) return null
        val key = try {
            store.getKey(KEY_ALIAS, null)
        } catch (error: Throwable) {
            throw DeviceSecretUnreadableException(error)
        }
        return key as? SecretKey ?: throw DeviceSecretUnreadableException()
    }

    @Synchronized
    private fun destroy(context: Context) {
        val preferences = context.getSharedPreferences(STATE_PREFERENCES, Context.MODE_PRIVATE)
        // Keep the recovery token/canary until irreversible key deletion has
        // succeeded. If deletion fails, the journal can still redeem its token
        // on the next launch and retry the reset.
        KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(KEY_ALIAS)
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("Could not clear device-secret state")
        }
        migrationAuditPending = false
        resetAuthorizationAvailable = false
    }

    @JvmStatic
    @Synchronized
    fun issueResetAuthorization(context: Context): String {
        if (!resetAuthorizationAvailable) {
            throw IllegalStateException("Device-vault recovery is not authorized")
        }
        val token = UUID.randomUUID().toString()
        val preferences = context.applicationContext.getSharedPreferences(
            STATE_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        if (!preferences.edit().putString(RESET_TOKEN_KEY, token).commit()) {
            throw IllegalStateException("Could not persist device-reset authorization")
        }
        return token
    }

    @JvmStatic
    fun validateResetAuthorization(context: Context, token: String?): Boolean {
        if (token.isNullOrEmpty()) return false
        val stored = context.applicationContext.getSharedPreferences(
            STATE_PREFERENCES,
            Context.MODE_PRIVATE,
        ).getString(RESET_TOKEN_KEY, null) ?: return false
        return MessageDigest.isEqual(
            stored.toByteArray(Charsets.UTF_8),
            token.toByteArray(Charsets.UTF_8),
        )
    }

    @JvmStatic
    fun clearResetAuthorization(context: Context) {
        val preferences = context.applicationContext.getSharedPreferences(
            STATE_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        if (!preferences.edit().remove(RESET_TOKEN_KEY).commit()) {
            throw IllegalStateException("Could not clear device-reset authorization")
        }
    }

    private fun errorCode(error: Throwable): String = when (error) {
        is DeviceSecretMissingException -> "device_secret_missing"
        is DeviceSecretUnreadableException -> "device_secret_unreadable"
        is DeviceSecretRecordUnreadableException -> "device_secret_record_unreadable"
        else -> "device_secret_failed"
    }

    private fun diagnosticDescription(operation: String, error: Throwable): String {
        var root = error
        while (root.cause != null && root.cause !== root) root = root.cause!!
        // Class names identify the broken provider operation without exposing
        // plaintext, AAD, an envelope, a URL, or a credential-bearing message.
        return "$operation:${error.javaClass.name}:${root.javaClass.name}"
    }

    private fun decodeArgument(value: String?): ByteArray {
        require(!value.isNullOrEmpty()) { "Missing channel argument" }
        return Base64.decode(value, Base64.NO_WRAP)
    }

    private class DeviceSecretMissingException : IllegalStateException(
        "The device-secret key is missing",
    )

    private class DeviceSecretUnreadableException(cause: Throwable? = null) :
        IllegalStateException("The device-secret key cannot open its canary", cause)

    private class DeviceSecretRecordUnreadableException(cause: Throwable) :
        IllegalStateException("The saved credential cannot be authenticated", cause)
}
