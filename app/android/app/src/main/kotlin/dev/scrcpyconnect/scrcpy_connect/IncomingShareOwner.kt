package dev.scrcpyconnect.scrcpy_connect

import java.lang.ref.WeakReference
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicBoolean

/** 进程分享资源登记；Activity 只决定准入，不能以销毁代替复制排空。 */
internal class IncomingShareOwner<T>(
    private val close: (T) -> Unit,
    private val capacity: Int = 256,
    private val openingCapacity: Int = 8,
) {
    private var activity: WeakReference<Any>? = null
    private var claimant: WeakReference<Any>? = null
    private var lease: String? = null
    private var ready = false
    private val resources = linkedMapOf<String, IncomingShareOpen<T>>()

    @Synchronized fun attach(caller: Any): List<IncomingShareOpen<T>> {
        if (activity?.get() === caller) return emptyList()
        activity = WeakReference(caller)
        claimant = null
        ready = false
        return resources.values.toList()
    }
    @Synchronized fun detach(caller: Any): List<IncomingShareOpen<T>> {
        if (activity?.get() !== caller) return emptyList()
        activity = null
        claimant = null
        ready = false
        return resources.values.toList()
    }
    @Synchronized fun current(caller: Any): Boolean = activity?.get() === caller
    @Synchronized fun lease(): String? = lease
    @Synchronized fun accepts(candidate: String?): Boolean =
        activity?.get() != null && ready && lease != null && lease == candidate

    /** null 表示同候选的成功确认已存在；其他情况须先排空返回的全部精确资源。 */
    @Synchronized fun claim(caller: Any, expected: String?, candidate: String): List<IncomingShareOpen<T>>? {
        check(current(caller)) {"分享页面已分离。"}
        check(candidate.isNotBlank() && candidate.length <= 128) {"分享平台代次无效。"}
        if (lease == candidate && ready) return null
        check(lease == candidate || lease == expected) {"分享平台已由更新代次接管。"}
        lease = candidate
        ready = false
        claimant = WeakReference(caller)
        return resources.values.toList()
    }
    @Synchronized fun complete(caller: Any, candidate: String): Boolean {
        if (!current(caller) || claimant?.get() !== caller || lease != candidate || resources.isNotEmpty()) return false
        ready = true
        return true
    }
    @Synchronized fun register(caller: Any, candidate: String, id: String, descriptorId: String,
        cancelReply: () -> Unit): IncomingShareOpen<T> {
        check(current(caller) && accepts(candidate)) {"分享平台尚未完成恢复。"}
        check(id.isNotBlank() && id.length <= 256 && !resources.containsKey(descriptorId)) {"分享打开标识无效。"}
        check(resources.size < capacity && resources.values.count {!it.finished.isDone} < openingCapacity) {"分享读取队列已满。"}
        check(resources.values.none {it.ownerLease == candidate && it.id == id}) {"分享打开标识重复。"}
        return IncomingShareOpen(id, descriptorId, candidate, close, cancelReply).also {resources[descriptorId] = it}
    }
    @Synchronized fun byOpen(caller: Any, candidate: String?, id: String): List<IncomingShareOpen<T>> {
        check(current(caller) && !candidate.isNullOrBlank()) {"分享清理不属于当前页面。"}
        return resources.values.filter {it.ownerLease == candidate && it.id == id}
    }
    @Synchronized fun byDescriptor(caller: Any, candidate: String?, id: String): List<IncomingShareOpen<T>> {
        check(current(caller) && !candidate.isNullOrBlank()) {"分享清理不属于当前页面。"}
        val resource = resources[id] ?: return emptyList()
        check(resource.ownerLease == candidate) {"分享描述符不属于本次代次。"}
        return listOf(resource)
    }
    @Synchronized fun forget(resource: IncomingShareOpen<T>) {
        check(resource.finished.isDone && resource.released) {"分享资源关闭尚未确认。"}
        if (resources[resource.descriptorId] === resource) resources.remove(resource.descriptorId)
    }
}

/** 迟到打开也先交还登记；只有真实 worker 结束及原描述符关闭后才能移除所有权。 */
internal class IncomingShareOpen<T>(
    val id: String,
    val descriptorId: String,
    val ownerLease: String,
    private val close: (T) -> Unit,
    private val cancelReply: () -> Unit,
) {
    val cancelled = AtomicBoolean()
    val finished = CompletableFuture<Unit>()
    private var resource: T? = null
    @Synchronized fun opened(value: T) {
        check(resource == null) {"分享描述符重复交付。"}
        resource = value
    }
    @Synchronized fun value(): T? = resource
    @get:Synchronized val released: Boolean get() = resource == null
    fun cancel() {
        if (cancelled.compareAndSet(false, true)) cancelReply()
    }
    fun drain() {
        finished.join()
        synchronized(this) {
            resource?.let {close(it); resource = null}
        }
    }
}
