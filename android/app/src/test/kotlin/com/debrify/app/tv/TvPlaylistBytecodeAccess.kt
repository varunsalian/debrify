package com.debrify.app.tv

import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes

/** Adjacent private writes have no intermediate observable hook: pin compiled order too. */
internal object TvPlaylistBytecodeAccess {
    fun teardown(type: Class<*>): List<String> {
        val events=mutableListOf<String>()
        type.getResourceAsStream("AndroidTvTorrentPlayerActivity.class")!!.use { stream ->
            ClassReader(stream).accept(object: ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int,name: String,descriptor: String,signature: String?,exceptions: Array<out String>?): MethodVisitor? {
                    if(name!="onDestroy")return null
                    return object: MethodVisitor(Opcodes.ASM9) {
                        var lastField=""
                        override fun visitFieldInsn(opcode: Int,owner: String,name: String,descriptor: String) {
                            if(opcode==Opcodes.GETFIELD)lastField=name
                            if(opcode==Opcodes.PUTFIELD && name in listOf("playlistAdapter","seriesPlaylistAdapter","moviePlaylistAdapter","focusRecoveryRunnable"))events.add(name)
                        }
                        override fun visitMethodInsn(opcode: Int,owner: String,name: String,descriptor: String,isInterface: Boolean) {
                            val member = name.substringBefore('$')
                            if (owner == "com/debrify/app/tv/TvPlaylistOverlayController") {
                                when (member) {
                                    "setPlaylistAdapter" -> events.add("playlistAdapter")
                                    "setSeriesPlaylistAdapter" -> events.add("seriesPlaylistAdapter")
                                    "setMoviePlaylistAdapter" -> events.add("moviePlaylistAdapter")
                                    "getSeasonTabs" -> lastField = "seasonTabs"
                                    "getMovieTabs" -> lastField = "movieTabs"
                                }
                            }
                            if (owner == "com/debrify/app/tv/TvPlaylistFocusNavigator") {
                                when (member) {
                                    "getFocusRecoveryHandler" -> lastField = "focusRecoveryHandler"
                                    "setFocusRecoveryRunnable" -> events.add("focusRecoveryRunnable")
                                }
                            }
                            if(name=="removeCallbacksAndMessages" && lastField=="focusRecoveryHandler")events.add("focusRecoveryHandler.remove")
                            if(name=="clear" && lastField in listOf("seasonTabs","movieTabs"))events.add(lastField+".clear")
                        }
                    }
                }
            },0)
        }
        return events
    }
}
