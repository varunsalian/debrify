package com.debrify.app.audio

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Announces our playback audio session to system audio-effect apps — Wavelet,
 * OEM equalizers, Dolby/DTS — using the standard
 * ACTION_OPEN/CLOSE_AUDIO_EFFECT_CONTROL_SESSION broadcasts.
 *
 * Effect apps can only attach to a session id they know about, and the usual
 * way they learn it is this broadcast. Without it they fall back to scraping
 * the audio service (Wavelet's "enhanced session detection", which needs a
 * DUMP grant over ADB) or to the deprecated global session 0 ("legacy mode"),
 * neither of which is reliable. Both players announce through here:
 *
 *  - phone (media_kit/libmpv): the id is generated here and pinned into mpv
 *    via `audiotrack-session-id`, announced from the Dart player screen.
 *  - TV (ExoPlayer): the id comes from the player itself, announced when
 *    Media3 reports it (onAudioSessionIdChanged / STATE_READY).
 *
 * Exactly one session is announced at a time: [open] closes whatever was open
 * before. An unmatched OPEN leaks the effect for other apps, so every path out
 * of playback must reach [close]/[closeCurrent].
 */
object AudioEffectSession {
    const val CHANNEL = "com.debrify.app/audio_effects"
    private const val TAG = "AudioEffectSession"

    /** The session currently announced as open, or 0 when none is. */
    private var openSessionId = 0

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generateSessionId" -> result.success(generateSessionId(appContext))
                    "open" -> {
                        open(appContext, call.argument<Int>("sessionId") ?: 0)
                        result.success(null)
                    }
                    "close" -> {
                        close(appContext, call.argument<Int>("sessionId") ?: 0)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Reserve an audio session id from the framework. Returns 0 if the platform
     * won't give one out — callers should then just skip the announcement and
     * let mpv pick its own id (playback is unaffected either way).
     */
    fun generateSessionId(context: Context): Int {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val id = am.generateAudioSessionId()
            if (id == AudioManager.ERROR) 0 else id
        } catch (e: Exception) {
            Log.w(TAG, "generateAudioSessionId failed", e)
            0
        }
    }

    @Synchronized
    fun open(context: Context, sessionId: Int) {
        if (sessionId == 0) return
        if (sessionId == openSessionId) return
        // Never leave a previous session announced — effect apps would keep
        // their effects attached to audio that no longer exists.
        if (openSessionId != 0) close(context, openSessionId)
        try {
            val intent = Intent(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION).apply {
                putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
                // MUSIC is what the effect-app ecosystem expects players to
                // send; some effect apps ignore other content types entirely.
                putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
            }
            context.sendBroadcast(intent)
            openSessionId = sessionId
        } catch (e: Exception) {
            Log.w(TAG, "Failed to announce audio session $sessionId", e)
        }
    }

    @Synchronized
    fun close(context: Context, sessionId: Int) {
        if (sessionId == 0) return
        try {
            val intent = Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION).apply {
                putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release audio session $sessionId", e)
        } finally {
            if (openSessionId == sessionId) openSessionId = 0
        }
    }

    /** Release whatever is currently announced. Safe to call when nothing is. */
    @Synchronized
    fun closeCurrent(context: Context) {
        if (openSessionId != 0) close(context, openSessionId)
    }
}
