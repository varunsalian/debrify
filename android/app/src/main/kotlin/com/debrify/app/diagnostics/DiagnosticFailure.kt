package com.debrify.app.diagnostics

/** Android often wraps the useful player exception in an ActivityThread
 * exception. Keep bounded cause stacks, never exception messages/media data. */
internal object DiagnosticFailure {
    fun describe(error: Throwable): String = generateSequence(error) { it.cause }
        .take(4)
        .mapIndexed { index, cause ->
            "cause=$index type=${cause.javaClass.name} stack=" +
                cause.stackTrace.take(16).joinToString(" | ")
        }.joinToString(" ; ")
}
