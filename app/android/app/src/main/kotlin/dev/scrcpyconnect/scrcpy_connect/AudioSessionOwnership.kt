package dev.scrcpyconnect.scrcpy_connect

import java.util.WeakHashMap

/** 主线程系统租约所有权，不包含播放器或播放策略。 */
internal class AudioPlatformOwnership {
    private val visibleOwners = WeakHashMap<Any, Boolean>()
    var owner: String? = null
        private set
    var epoch: Long? = null
        private set
    private var lastEpoch = 0L
    var background = false
    val visible get() = visibleOwners.isNotEmpty()

    fun visible(activity: Any, value: Boolean): Boolean {
        val before = visible
        if (value) visibleOwners[activity] = true else visibleOwners.remove(activity)
        return before != visible
    }
    fun claim(id: String): Boolean {
        if (owner != null && owner != id) return false
        owner = id
        return true
    }
    fun nextEpoch(): Long {
        check(owner != null && epoch == null)
        check(lastEpoch < Long.MAX_VALUE)
        return (++lastEpoch).also { epoch = it }
    }
    fun clearEpoch(value: Long): Boolean {
        if (epoch != value) return false
        epoch = null
        return true
    }
    fun releaseIfUnused() { if (epoch == null && !background) owner = null }
}
