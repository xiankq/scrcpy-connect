package dev.scrcpyconnect.scrcpy_connect

/** 实际发现锁的状态切换，与重叠 Activity 独立。 */
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

/** 交接失败不等于平台资源已关闭；错误码供 Dart 保留精确清理责任。 */
internal class UsbLeaseFailure(val code: String, message: String, cause: Throwable? = null) :
    IllegalStateException(message, cause)

/** 原始 USB 描述符归进程所有；新代只有在 SDK 排空之后才能完成平台接管。 */
internal class UsbHandoffLeases<T>(private val capacity: Int, private val close: (T) -> Unit) {
    private class Entry<T>(val owner: String, var activity: Any?, val resource: T)
    private enum class Phase { SEALED, RECOVERING, READY }
    private val lock = Any()
    private val entries = mutableMapOf<String, Entry<T>>()
    private var owner: String? = null
    private var phase = Phase.SEALED

    private fun token(value: String?): String = value?.takeIf {
        it.isNotBlank() && it.length <= 256 && it.none { character -> character.isISOControl() }
    } ?: throw UsbLeaseFailure("usb_owner_stale", "缺少有效的 USB 技术租约。")

    fun validateToken(candidate: String?): String = token(candidate)

    fun environment(): Map<String, Any?> = synchronized(lock) {
        mapOf("ownerLeaseId" to owner, "ownerReady" to (phase == Phase.READY))
    }
    fun accepts(candidate: String?): Boolean = synchronized(lock) {
        candidate != null && candidate == owner && phase == Phase.READY
    }
    private fun requireReady(candidate: String) {
        if (phase != Phase.READY) throw UsbLeaseFailure("usb_recovery_pending", "USB 平台资源尚未完成接管。")
        if (owner != candidate) throw UsbLeaseFailure("usb_owner_stale", "USB 技术租约已被替换。")
    }
    fun checkAdmission(candidate: String?): String = synchronized(lock) {
        token(candidate).also { requireReady(it) }
    }
    fun checkCapacity(candidate: String?) = synchronized(lock) {
        requireReady(token(candidate))
        if (entries.size >= capacity) throw UsbLeaseFailure("usb_lease_limit", "USB 授权交接尚未完成，请先结束已有请求。")
    }
    /** 重启只封存准入，不关闭仍可能被 SDK 借用的描述符。 */
    fun seal() = synchronized(lock) { phase = Phase.SEALED }

    fun beginRecovery(expected: String?, candidate: String?): Map<String, Any?> = synchronized(lock) {
        val next = token(candidate)
        if (owner == next) {
            if (phase == Phase.SEALED) throw UsbLeaseFailure("usb_owner_stale", "已封存的旧代必须使用新候选接管。")
        } else {
            if (owner != expected) throw UsbLeaseFailure("usb_owner_stale", "USB 平台代次已被替换。")
            owner = next
            phase = Phase.RECOVERING
        }
        mapOf("begun" to true, "ownerLeaseId" to next, "ownerReady" to (phase == Phase.READY))
    }

    private fun requireRecovery(candidate: String) {
        if (owner != candidate) throw UsbLeaseFailure("usb_owner_stale", "USB 接管候选已被替换。")
        if (phase == Phase.SEALED) throw UsbLeaseFailure("usb_recovery_pending", "USB 平台尚未登记本次接管。")
    }
    /** 调用方必须先确认 SDK 握手、捕获和连接实际排空。关闭失败保留原条目。 */
    fun completeRecovery(candidate: String?): Map<String, Any?> {
        val next = token(candidate)
        val pending = synchronized(lock) {
            requireRecovery(next)
            if (phase == Phase.READY) return environment() + ("completed" to true)
            entries.toList()
        }
        var failure: Throwable? = null
        pending.forEach { (id, entry) ->
            try {
                // 等待同一描述符正在进行的关闭，不持有全局锁，后继仍可先封存旧候选。
                synchronized(entry) {
                    val present = synchronized(lock) {
                        requireRecovery(next)
                        entries[id] === entry
                    }
                    if (present) {
                        close(entry.resource)
                        synchronized(lock) { if (entries[id] === entry) entries.remove(id) }
                    }
                }
            } catch (error: Throwable) {
                val first = failure
                if (first == null) failure = error else if (first !== error) first.addSuppressed(error)
            }
        }
        return synchronized(lock) {
            requireRecovery(next)
            // 并发的同候选完成可能已经放行新资源；旧快照不能再把新资源视为清理残余。
            if (phase == Phase.READY) return environment() + ("completed" to true)
            if (failure != null || entries.isNotEmpty()) {
                throw UsbLeaseFailure("usb_cleanup_unconfirmed", "部分 USB 平台资源尚未确认关闭，请重试同一候选。", failure)
            }
            phase = Phase.READY
            environment() + ("completed" to true)
        }
    }

    /** 系统打开与登记共享封存锁；返回前一定已有可重试的原始资源所有者。 */
    fun open(id: String, activity: Any, candidate: String, create: () -> T?): T? = synchronized(lock) {
        requireReady(token(candidate))
        if (entries.size >= capacity || entries.containsKey(id)) {
            throw UsbLeaseFailure("usb_lease_limit", "USB 授权交接尚未完成，请先结束已有请求。")
        }
        val resource = create() ?: return null
        entries[id] = Entry(candidate, activity, resource)
        resource
    }

    fun register(id: String, activity: Any, candidate: String, resource: T): Boolean = synchronized(lock) {
        requireReady(token(candidate))
        if (entries.size >= capacity || entries.containsKey(id)) return false
        entries[id] = Entry(candidate, activity, resource)
        true
    }
    fun handoff(id: String, activity: Any, candidate: String): Boolean = synchronized(lock) {
        requireReady(token(candidate))
        val entry = entries[id] ?: return false
        if (entry.owner != candidate || entry.activity !== activity) return false
        entry.activity = null // 已交付的描述符不再保留 Activity。
        true
    }
    fun abandon(activity: Any) {
        val abandoned = synchronized(lock) { entries.filterValues { it.activity === activity }.toList() }
        var failure: Throwable? = null
        abandoned.forEach { (id, entry) ->
            try {
                synchronized(entry) {
                    synchronized(lock) {
                        // 交接可能已发生；Activity 不能用旧快照关闭已经交付的资源。
                        if (entries[id] === entry && entry.activity === activity) {
                            close(entry.resource)
                            entries.remove(id)
                        }
                    }
                }
            } catch (error: Throwable) {
                val first = failure
                if (first == null) failure = error else if (first !== error) first.addSuppressed(error)
            }
        }
        if (failure != null) throw UsbLeaseFailure("usb_cleanup_unconfirmed", "未交付 USB 资源关闭尚未确认。", failure)
    }
    fun release(id: String?, candidate: String?): Boolean {
        val lease = token(candidate)
        if (id.isNullOrBlank()) throw UsbLeaseFailure("usb_owner_stale", "缺少精确 USB 资源租约。")
        val entry = synchronized(lock) {
            // 封存期间连已不存在的 ID 也不能返回成功，防止调用方误认为 SDK 已排空。
            if (phase != Phase.READY) throw UsbLeaseFailure("usb_recovery_pending", "USB 平台正在等待 SDK 排空。")
            val found = entries[id] ?: return false
            requireReady(lease)
            if (found.owner != lease) throw UsbLeaseFailure("usb_owner_stale", "USB 资源属于另一技术租约。")
            found
        }
        return synchronized(entry) {
            synchronized(lock) {
                if (phase != Phase.READY) throw UsbLeaseFailure("usb_recovery_pending", "USB 平台正在等待 SDK 排空。")
                if (entries[id] !== entry) return false
                requireReady(lease)
                try {
                    // 普通释放与封存在同一临界区线性化；封存返回后旧释放不能再开始关闭。
                    close(entry.resource)
                } catch (error: Throwable) {
                    throw UsbLeaseFailure("usb_cleanup_unconfirmed", "USB 平台关闭尚未确认，请重试原租约。", error)
                }
                entries.remove(id)
                true
            }
        }
    }
}

/** 授权 UI 的撤销只匹配创建时的 owner 和 attempt，不代表 SDK 或原始 FD 已经释放。 */
internal class UsbPermissionRequests {
    private class Request(val owner: String, val attempt: String?, val cancel: () -> Unit)
    private var pending: Request? = null
    @Synchronized fun owner(): String? = pending?.owner
    @Synchronized fun begin(owner: String, attempt: String?, cancel: () -> Unit) {
        check(pending == null) { "已有 USB 授权 UI 正在等待。" }
        pending = Request(owner, attempt, cancel)
    }
    @Synchronized fun clear() { pending = null }
    fun cancel(owner: String, attempt: String?): Boolean {
        val action = synchronized(this) {
            val request = pending ?: return false
            if (attempt == null || request.owner != owner || request.attempt != attempt) return false
            // 外部回调抛错或重入时也不能重新取消后继请求。
            pending = null
            request.cancel
        }
        action()
        return true
    }
}
