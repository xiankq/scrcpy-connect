package dev.scrcpyconnect.scrcpy_connect

/** Physical discovery lock transitions, independent of overlapping Activities. */
internal class DiscoveryLeaseOwners {
    private val owners = mutableSetOf<Any>()
    @Synchronized fun acquire(owner: Any, activate: () -> Boolean): Boolean {
        if (owners.contains(owner)) return true
        if (owners.isEmpty() && !activate()) return false
        owners.add(owner)
        return true
    }
    @Synchronized fun release(owner: Any, deactivate: () -> Unit) {
        if (owners.remove(owner) && owners.isEmpty()) deactivate()
    }
}

/** Java USB descriptors are borrowed by an asynchronous Rust operation.
 * Before handoff, the requesting Activity may abandon them; after handoff only
 * the exact operation ACK may close them. No timeout may race Rust's fd dup.
 */
internal class UsbHandoffLeases<T>(private val capacity: Int, private val close: (T) -> Unit) {
    private class Entry<T>(var activity: Any?, val resource: T)
    private val lock = Any()
    private val entries = mutableMapOf<String, Entry<T>>()

    fun register(id: String, activity: Any, resource: T): Boolean = synchronized(lock) {
        if (entries.size >= capacity || entries.containsKey(id)) return false
        entries[id] = Entry(activity, resource)
        true
    }
    fun handoff(id: String, activity: Any): Boolean = synchronized(lock) {
        val entry = entries[id] ?: return false
        if (entry.activity !== activity) return false
        entry.activity = null // Do not retain the Activity after returning its fd.
        true
    }
    fun abandon(activity: Any) {
        val abandoned = synchronized(lock) {
            val items = entries.filterValues { it.activity === activity }
            items.keys.forEach { entries.remove(it) }
            items.values.map { it.resource }
        }
        abandoned.forEach(close)
    }
    fun release(id: String?): Boolean {
        val resource = synchronized(lock) { entries.remove(id)?.resource } ?: return false
        close(resource)
        return true
    }
}
