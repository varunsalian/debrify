package com.debrify.app.tv

import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes

/** Pin adjacent handler/effect operations whose intermediate order has no callback seam. */
internal object TvControlsLifecycleBytecode {
    fun destroyOrder(): List<String> {
        val events = mutableListOf<String>()
        AndroidTvTorrentPlayerActivity::class.java.getResourceAsStream("AndroidTvTorrentPlayerActivity.class")!!.use { input ->
            ClassReader(input).accept(object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int, name: String, descriptor: String, signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                    if (name != "onDestroy") return null
                    return object : MethodVisitor(Opcodes.ASM9) {
                        var field = ""
                        override fun visitFieldInsn(opcode: Int, owner: String, name: String, descriptor: String) { if (opcode == Opcodes.GETFIELD) field = name }
                        override fun visitMethodInsn(opcode: Int, owner: String, name: String, descriptor: String, isInterface: Boolean) {
                            when (name.substringBefore('$')) {
                                "getControlsHandler" -> field = "controlsHandler"
                                "getSeekbarHandler" -> field = "seekbarHandler"
                                "removeCallbacksAndMessages" -> if (field in listOf("progressHandler", "controlsHandler", "seekbarHandler")) events.add(field)
                                "releaseLoudnessEnhancer" -> events.add("releaseEffect")
                            }
                        }
                    }
                }
            }, 0)
        }
        return events
    }
}
