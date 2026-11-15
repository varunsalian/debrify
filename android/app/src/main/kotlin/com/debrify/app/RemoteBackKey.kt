package com.debrify.app

import android.view.KeyEvent

/**
 * Remotes that present themselves as a keyboard (many Wi-Fi and air-mouse
 * remotes) send Escape for their Back key, and gamepads send B. Android only
 * turns these into Back as a fallback for keys an app leaves unhandled, and a
 * Flutter view claims every key before re-dispatching the unhandled ones
 * itself, so that fallback never happens: Back did nothing with such remotes.
 *
 * Each activity rewrites them to KEYCODE_BACK on entry, so Flutter and the
 * native players see an ordinary Back press and an unhandled one still ends in
 * onBackPressed. Escape with any modifier (Shift, Alt, Ctrl, Meta, ...) keeps
 * its keyboard meaning.
 *
 * Known limits: the rewrite happens after a visible system keyboard has seen
 * the raw key, so Escape there acts on the screen rather than first closing
 * that keyboard; and on Android 16+ (predictive back) an unhandled rewritten
 * Back is not yet verified to reach onBackPressed.
 */
object RemoteBackKey {
    @JvmStatic
    fun isRemoteBack(event: KeyEvent): Boolean = when (event.keyCode) {
        KeyEvent.KEYCODE_ESCAPE -> event.hasNoModifiers()
        KeyEvent.KEYCODE_BUTTON_B -> true
        else -> false
    }

    /**
     * [event] as a Back press when it is a remote's Back, otherwise the SAME
     * instance: Flutter recognises its own re-dispatched events by identity,
     * so copying any other event (including a real Back) would make it
     * re-dispatch forever.
     */
    @JvmStatic
    fun normalize(event: KeyEvent): KeyEvent {
        if (!isRemoteBack(event)) return event
        return KeyEvent(
            event.downTime,
            event.eventTime,
            event.action,
            KeyEvent.KEYCODE_BACK,
            event.repeatCount,
            event.metaState,
            event.deviceId,
            event.scanCode,
            event.flags,
            event.source,
        )
    }
}
