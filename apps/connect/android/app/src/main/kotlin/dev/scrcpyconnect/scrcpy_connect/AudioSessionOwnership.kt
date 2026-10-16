package dev.scrcpyconnect.scrcpy_connect

import java.util.WeakHashMap

internal interface OwnedAudio : AutoCloseable {
    fun background(paused: Boolean): Map<String, Any?>
    fun status(): Map<String, Any?>
}

/** Activity bindings own presentation, never the lifetime of an explicitly opened audio source. */
internal class AudioSessionOwnership(private val changed: (Map<String, Any?>) -> Unit) {
    private val visible = WeakHashMap<Any, Boolean>()
    private val sources = linkedMapOf<String, OwnedAudio>()
    fun setVisible(owner: Any, value: Boolean) { if (value) visible[owner] = true else visible.remove(owner); apply() }
    var backgroundAllowed = false
        set(value) { field = value; apply() }
    fun isVisible() = visible.isNotEmpty()
    fun add(id: String, source: OwnedAudio) { check(!sources.containsKey(id)); sources[id] = source; apply() }
    fun get(id: String?) = sources[id]
    fun snapshots() = sources.values.map { it.status() }
    fun empty() = sources.isEmpty()
    fun remove(id: String?) { sources.remove(id)?.close() }
    fun stopAll() { val old = sources.values.toList(); sources.clear(); old.forEach { it.close() } }
    private fun apply() {
        val paused = !isVisible() && !backgroundAllowed
        sources.values.toList().forEach { source ->
            val receipt = source.background(paused)
            if (receipt["applied"] == true) changed(receipt)
        }
    }
}
