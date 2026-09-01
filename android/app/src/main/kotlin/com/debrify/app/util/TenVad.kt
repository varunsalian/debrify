package com.debrify.app.util

/**
 * A frame-level voice-activity detector the speech feature tap can consult:
 * 16 kHz mono int16 hops of [hopSize] samples in, a speech probability out.
 */
interface FrameVad {
    val hopSize: Int

    /** Probability in [0, 1], or a negative value when the detector failed. */
    fun probability(hop: ShortArray): Float

    fun close()
}

/**
 * ten-vad (Agora's neural VAD) behind a JNI shim. Loading is lazy and
 * fail-closed: on an ABI without the prebuilt, or if either library refuses
 * to load, [create] returns null and the caller keeps its energy features.
 * See android/app/third_party/ten-vad/README.md for provenance and licence.
 *
 * Threading: one instance, one thread. The tap calls it only from its
 * feature worker.
 */
class TenVad private constructor(
    private var handle: Long,
    override val hopSize: Int,
) : FrameVad {

    private val scratch = FloatArray(1)

    override fun probability(hop: ShortArray): Float {
        val h = handle
        if (h == 0L || hop.size != hopSize) return -1f
        val flag = nativeProcess(h, hop, hopSize, scratch)
        return if (flag < 0) -1f else scratch[0].coerceIn(0f, 1f)
    }

    override fun close() {
        val h = handle
        handle = 0L
        if (h != 0L) nativeDestroy(h)
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        const val DEFAULT_HOP = 256 // 16 ms at 16 kHz
        const val DEFAULT_THRESHOLD = 0.5f

        /** Human-readable load state for the AutoSync log line. */
        @Volatile
        var availability: String = "not loaded"
            private set

        private val loaded: Boolean by lazy {
            try {
                System.loadLibrary("ten_vad")
                System.loadLibrary("debrify_tenvad")
                availability = "ten-vad ${nativeVersion()}"
                true
            } catch (e: Throwable) {
                // UnsatisfiedLinkError on ABIs without the prebuilt, or any
                // loader surprise: the feature must degrade, never crash.
                availability = "unavailable (${e.javaClass.simpleName}: ${e.message})"
                false
            }
        }

        fun create(hopSize: Int = DEFAULT_HOP, threshold: Float = DEFAULT_THRESHOLD): TenVad? {
            if (!loaded) return null
            val handle = try {
                nativeCreate(hopSize, threshold)
            } catch (e: Throwable) {
                availability = "create failed (${e.javaClass.simpleName})"
                0L
            }
            return if (handle == 0L) null else TenVad(handle, hopSize)
        }

        @JvmStatic private external fun nativeCreate(hopSize: Int, threshold: Float): Long
        @JvmStatic private external fun nativeProcess(handle: Long, audio: ShortArray, length: Int, out: FloatArray): Int
        @JvmStatic private external fun nativeDestroy(handle: Long)
        @JvmStatic private external fun nativeVersion(): String
    }
}
