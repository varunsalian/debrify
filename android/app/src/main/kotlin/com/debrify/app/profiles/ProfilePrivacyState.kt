package com.debrify.app.profiles

import android.content.Context

/**
 * Native launch/background privacy state published while Flutter is active.
 *
 * The background policy is durable because Android may recreate MainActivity
 * before Dart has rendered a frame. A profile configured to lock on resume
 * must therefore start secure and set FLAG_SECURE synchronously on pause,
 * rather than waiting for Dart's eventual resumed callback.
 */
object ProfilePrivacyState {
    private const val PREFS_NAME = "debrify_profile_privacy"
    private const val KEY_SENSITIVE = "sensitive"
    private const val KEY_PROTECT_ON_BACKGROUND = "protect_on_background"

    @JvmStatic
    fun update(
        context: Context,
        sensitive: Boolean,
        protectOnBackground: Boolean,
    ) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SENSITIVE, sensitive)
            .putBoolean(KEY_PROTECT_ON_BACKGROUND, protectOnBackground)
            // The next onPause/onCreate is a native security boundary. Commit
            // keeps it crash-safe instead of leaving a pending apply behind.
            .commit()
    }

    @JvmStatic
    fun shouldProtectWhenBackgrounded(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // Missing state is fail-closed until Flutter publishes the active
        // profile. An unlocked profile immediately clears the launch flag.
        return prefs.getBoolean(KEY_SENSITIVE, true) ||
            prefs.getBoolean(KEY_PROTECT_ON_BACKGROUND, false)
    }
}
