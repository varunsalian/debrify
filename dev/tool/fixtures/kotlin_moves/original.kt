@file:Suppress("unused")
package fixture

import kotlin.math.abs

// Activity annotation is part of its checked header.
@OptIn(ExperimentalStdlibApi::class)
class Activity {
    val first = 1_000L
    val second = 2u
    init { first() }
    init { second() }
    val delegated by lazy { object { val value = "nested"; init { second() } } }
    fun overloaded(value: Int) = value + 1
    fun overloaded(value: String) = value + "!"
    fun statements() {
        first()
        second()
    }
    fun multiline() = (1
        + 2)
    fun `back tick`() = run label@ { return@label this@Activity }

    /** Move this KDoc and the nested /* block */ comment. */
    private data class Model(val id: Int, val name: String) {
        val template = "hello $name ${"nested ${id + 1}"}"
        val raw = """raw $name ${id}"""
        val character = '\n'
        val objectValue = object { val value = 7; init { println(value) } }
        fun expression() = id + 2
    }
}
