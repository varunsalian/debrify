package com.debrify.app.tv

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackReturnHandoffTest {
    @Test
    fun `claim identifies the returning session without authorizing older journals`() {
        val ledger = PlaybackReturnLedger(nowMs = { 1_000L })
        ledger.begin(8, "adult", 3)
        ledger.markReturning(8)
        assertEquals(8, ledger.consumeSession("adult", 3))
        assertNull(ledger.consumeSession("adult", 3))
    }

    @Test
    fun `same live playback owner gets one return claim`() {
        var now = 1_000L
        val ledger = PlaybackReturnLedger(nowMs = { now })
        ledger.begin(7, "adult", 3)
        ledger.markReturning(7)

        assertTrue(ledger.consume("adult", 3))
        assertFalse(ledger.consume("adult", 3))
    }

    @Test
    fun `wrong profile consumes but never unlocks the handoff`() {
        val ledger = PlaybackReturnLedger(nowMs = { 1_000L })
        ledger.begin(7, "adult", 3)
        ledger.markReturning(7)

        assertFalse(ledger.consume("kids", 3))
        assertFalse(ledger.consume("adult", 3))
    }

    @Test
    fun `cold active session and expired return both fail closed`() {
        var now = 1_000L
        val ledger = PlaybackReturnLedger(nowMs = { now }, ttlMs = 30_000L)
        ledger.begin(7, "adult", 3)
        assertFalse(ledger.consume("adult", 3))

        ledger.begin(8, "adult", 3)
        ledger.markReturning(8)
        now += 30_001L
        assertFalse(ledger.consume("adult", 3))
    }

    @Test
    fun `stale player cannot mark a newer session returning`() {
        val ledger = PlaybackReturnLedger(nowMs = { 1_000L })
        ledger.begin(8, "adult", 3)
        ledger.markReturning(7)

        assertFalse(ledger.consume("adult", 3))
    }
}
