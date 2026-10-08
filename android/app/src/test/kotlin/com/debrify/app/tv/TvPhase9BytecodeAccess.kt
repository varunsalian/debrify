package com.debrify.app.tv

import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes

/** Exact teardown ordering cannot be observed between adjacent private writes.
 * Inspect the compiled original method; behavioural tests also run real teardown.
 * A move retargets this helper's field-access representation, retaining the sequence.
 */
internal object TvPhase9BytecodeAccess {
    fun teardown(type: Class<*>): List<String> {
        val events = mutableListOf<String>()
        val stream = type.getResourceAsStream("AndroidTvTorrentPlayerActivity.class")!!
        stream.use { input ->
            ClassReader(input).accept(object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int, name: String, descriptor: String, signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                    if (name != "onDestroy") return null
                    return object : MethodVisitor(Opcodes.ASM9) {
                        var inside = false
                        override fun visitMethodInsn(opcode: Int, owner: String, name: String, descriptor: String, isInterface: Boolean) {
                            if (owner.endsWith("/TvStartupGateController")) {
                                val member = name.substringBefore('$')
                                if (member == "getStartupFailoverTimeout") inside = true
                                if (inside && member.startsWith("set")) {
                                    val property = member.removePrefix("set").replaceFirstChar { it.lowercase() }
                                    events.add(property)
                                    if (property == "startupFailoverCursor") inside = false
                                }
                            }
                            if (inside && name == "removeCallbacks") events.add("remove")
                        }
                    }
                }
            }, 0)
        }
        return events
    }
}
