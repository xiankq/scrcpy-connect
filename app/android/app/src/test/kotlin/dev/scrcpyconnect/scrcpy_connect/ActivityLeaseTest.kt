package dev.scrcpyconnect.scrcpy_connect

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/** 通过可观测的系统申请与关闭端口驱动生产所有权实现。 */
object ActivityLeaseTest {
    private class Descriptor {
        var closes = 0
        fun assertOpen() { check(closes == 0) }
        fun close() { closes++; check(closes == 1) }
    }
    @JvmStatic fun main(args: Array<String>) {
        discoveryOverlap()
        usbHandoffOverlap()
        boundedOutstandingHandoffs()
        failedUsbCloseRetainsOwner()
        failedAbandonStillClosesOtherDescriptors()
        coldOwnerAndSealedRestart()
        twoPhaseRecoveryAndLostReplies()
        failedRecoveryRetainsOwnerAndCapacity()
        successorDuringActualClose()
        openingAndRegistrationAreAtomic()
        ordinaryReleaseFinishesBeforeSeal()
        synchronousCloseReentryCannotCompleteSuccessor()
        exactPermissionCancellationAfterSeal()
        println("PASS: Activity overlap, USB two-phase recovery, exact ownership, close retry and concurrent handoff")
    }
    private fun readyOwnership(capacity: Int, close: (Descriptor) -> Unit): UsbHandoffLeases<Descriptor> =
        UsbHandoffLeases(capacity, close).also {
            it.beginRecovery(null, "owner")
            it.completeRecovery("owner")
        }
    private fun failure(code: String, action: () -> Unit) {
        val error = runCatching(action).exceptionOrNull()
        check(error is UsbLeaseFailure && error.code == code) { "expected $code, got $error" }
    }
    private fun await(latch: CountDownLatch) {
        check(latch.await(5, TimeUnit.SECONDS)) { "ownership gate did not settle" }
    }
    private fun finish(worker: Thread) {
        worker.join(5000)
        check(!worker.isAlive) { "ownership worker did not finish" }
    }
    private fun discoveryOverlap() {
        val ownership = DiscoveryLeaseOwners()
        val a = Any(); val b = Any(); val service = "background"
        var physicalAcquires = 0; var physicalReleases = 0
        fun start(owner: Any) = ownership.acquire(owner) { physicalAcquires++; true }
        fun stop(owner: Any) = ownership.release(owner) { physicalReleases++ }
        check(start(a)); check(start(a)); check(start(b))
        stop(a) // B 启动后 A 停止仍须保留 B 的实际锁。
        stop(a) // A 销毁属于重复释放，不能释放 B 的租约。
        check(physicalAcquires == 1 && physicalReleases == 0)
        check(start(service)); stop(b)
        check(physicalReleases == 0)
        stop(service); stop(b)
        check(physicalReleases == 1)
        check(!ownership.acquire(a) { false })
        stop(a) // 系统申请失败不能创建可释放所有者。
        check(physicalReleases == 1)
        check(start(b)); stop(b)
        check(physicalAcquires == 2 && physicalReleases == 2)
    }
    private fun usbHandoffOverlap() {
        val ownership = readyOwnership(4) { it.close() }
        val a = Any(); val b = Any()
        val aPending = Descriptor(); val aOffered = Descriptor(); val bPending = Descriptor()
        check(ownership.register("a-pending", a, "owner", aPending))
        check(ownership.register("a-offered", a, "owner", aOffered))
        check(!ownership.handoff("a-offered", b, "owner")) // 其他 Activity 不能取得待处理请求。
        check(ownership.handoff("a-offered", a, "owner"))
        check(ownership.register("b-pending", b, "owner", bPending))
        ownership.abandon(a)
        check(aPending.closes == 1)
        aOffered.assertOpen() // A 销毁不能使传递给 Rust 的描述符失效。
        bPending.assertOpen()
        check(ownership.handoff("b-pending", b, "owner"))
        ownership.abandon(a); ownership.abandon(b)
        aOffered.assertOpen(); bPending.assertOpen()
        check(ownership.release("a-offered", "owner")) // 精确 SDK 尝试或连接已结束，允许释放 A 的原平台租约。
        check(!ownership.release("a-offered", "owner"))
        check(!ownership.release("a-pending", "owner"))
        bPending.assertOpen() // A 的迟到释放不能关闭 B 已接受的描述符。
        check(ownership.release("b-pending", "owner"))
        check(aOffered.closes == 1 && bPending.closes == 1)
    }
    private fun boundedOutstandingHandoffs() {
        val ownership = readyOwnership(1) { it.close() }
        val a = Any(); val b = Any()
        val first = Descriptor(); val rejected = Descriptor()
        check(ownership.register("first", a, "owner", first))
        check(ownership.handoff("first", a, "owner"))
        ownership.abandon(a)
        check(!ownership.register("second", b, "owner", rejected))
        rejected.close() // 准入失败时调用方保留所有权。
        first.assertOpen()
        check(ownership.release("first", "owner"))
        val next = Descriptor()
        check(ownership.register("next", b, "owner", next))
        ownership.abandon(b)
        check(next.closes == 1 && first.closes == 1)
    }
    private fun failedUsbCloseRetainsOwner() {
        var fail = true
        val ownership = readyOwnership(1) {
            if (fail) { fail = false; error("模拟平台关闭失败") }
            it.close()
        }
        val activity = Any(); val descriptor = Descriptor()
        check(ownership.register("exact", activity, "owner", descriptor))
        check(ownership.handoff("exact", activity, "owner"))
        check(runCatching { ownership.release("exact", "owner") }.isFailure)
        descriptor.assertOpen()
        val rejected = Descriptor()
        check(!ownership.register("other", Any(), "owner", rejected))
        rejected.close()
        check(ownership.release("exact", "owner"))
        check(!ownership.release("exact", "owner"))
        check(descriptor.closes == 1)
    }
    private fun failedAbandonStillClosesOtherDescriptors() {
        val failed = Descriptor(); val other = Descriptor()
        var fail = true
        val ownership = readyOwnership(2) {
            if (it === failed && fail) { fail = false; error("模拟放弃时关闭失败") }
            it.close()
        }
        val activity = Any()
        check(ownership.register("failed", activity, "owner", failed))
        check(ownership.register("other", activity, "owner", other))
        check(runCatching { ownership.abandon(activity) }.isFailure)
        check(other.closes == 1)
        failed.assertOpen()
        ownership.abandon(activity)
        check(failed.closes == 1 && other.closes == 1)
        check(!ownership.release("failed", "owner"))
    }
    private fun coldOwnerAndSealedRestart() {
        val ownership = UsbHandoffLeases<Descriptor>(2) { it.close() }
        check(ownership.environment() == mapOf("ownerLeaseId" to null, "ownerReady" to false))
        failure("usb_recovery_pending") { ownership.checkAdmission("cold") }
        failure("usb_owner_stale") { ownership.beginRecovery(null, "") }
        failure("usb_owner_stale") { ownership.beginRecovery(null, "x".repeat(257)) }
        failure("usb_owner_stale") { ownership.beginRecovery(null, "bad\u0000token") }
        failure("usb_owner_stale") { ownership.beginRecovery("wrong", "first") }
        failure("usb_owner_stale") { ownership.completeRecovery("unregistered") }
        val begun = ownership.beginRecovery(null, "first")
        check(begun == mapOf("begun" to true, "ownerLeaseId" to "first", "ownerReady" to false))
        check(ownership.beginRecovery(null, "first") == begun) // 第一次 begin 的回执丢失。
        ownership.completeRecovery("first")
        val descriptor = Descriptor()
        check(ownership.register("held", Any(), "first", descriptor))
        ownership.seal()
        descriptor.assertOpen()
        failure("usb_recovery_pending") { ownership.completeRecovery("first") }
        failure("usb_owner_stale") { ownership.beginRecovery("first", "first") }
        failure("usb_recovery_pending") { ownership.release("held", "first") }
        ownership.beginRecovery("first", "next")
        descriptor.assertOpen()
        ownership.completeRecovery("next")
        check(descriptor.closes == 1)
    }
    private fun twoPhaseRecoveryAndLostReplies() {
        val ownership = readyOwnership(2) { it.close() }
        val oldActivity = Any(); val newActivity = Any(); val original = Descriptor()
        check(ownership.register("original", oldActivity, "owner", original))
        check(ownership.handoff("original", oldActivity, "owner"))
        ownership.beginRecovery("owner", "next")
        original.assertOpen() // SDK 的旧 disconnect 即使已返回，也不能提前关闭平台 FD。
        failure("usb_recovery_pending") { ownership.release("original", "owner") }
        failure("usb_recovery_pending") { ownership.release("already-absent", "owner") }
        failure("usb_recovery_pending") { ownership.handoff("original", oldActivity, "owner") }
        var opened = false
        failure("usb_recovery_pending") {
            ownership.open("late", oldActivity, "owner") { opened = true; Descriptor() }
        }
        check(!opened)
        ownership.abandon(oldActivity)
        original.assertOpen()
        check(ownership.completeRecovery("next") == mapOf("completed" to true, "ownerLeaseId" to "next", "ownerReady" to true))
        check(original.closes == 1)
        val successor = Descriptor()
        check(ownership.register("new-resource", newActivity, "next", successor))
        check(ownership.handoff("new-resource", newActivity, "next"))
        // begin 与 complete 的成功回执都可能丢失；相同候选重复确认不清理后来交付的资源。
        check(ownership.beginRecovery("owner", "next")["ownerReady"] == true)
        ownership.completeRecovery("next")
        successor.assertOpen()
        check(!ownership.release("original", "owner"))
        failure("usb_owner_stale") { ownership.release("new-resource", "owner") }
        failure("usb_owner_stale") { ownership.beginRecovery("owner", "stale") }
        failure("usb_owner_stale") { ownership.completeRecovery("owner") }
        failure("usb_owner_stale") { ownership.release("", "next") }
        failure("usb_owner_stale") { ownership.release("new-resource", null) }
        ownership.abandon(oldActivity)
        successor.assertOpen()
        check(ownership.release("new-resource", "next"))
    }
    private fun failedRecoveryRetainsOwnerAndCapacity() {
        val failed = Descriptor(); val other = Descriptor()
        var attempts = 0
        val ownership = readyOwnership(2) {
            if (it === failed && attempts++ == 0) error("first close failed")
            it.close()
        }
        val activity = Any()
        ownership.register("failed", activity, "owner", failed)
        ownership.handoff("failed", activity, "owner")
        ownership.register("other", activity, "owner", other)
        ownership.handoff("other", activity, "owner")
        ownership.beginRecovery("owner", "next")
        failure("usb_cleanup_unconfirmed") { ownership.completeRecovery("next") }
        check(other.closes == 1)
        failed.assertOpen()
        check(ownership.environment()["ownerReady"] == false)
        failure("usb_recovery_pending") { ownership.checkCapacity("next") }
        check(ownership.beginRecovery("owner", "next")["ownerReady"] == false)
        ownership.completeRecovery("next")
        check(attempts == 2 && failed.closes == 1 && other.closes == 1)
        val fresh = Descriptor()
        check(ownership.register("fresh", activity, "next", fresh))
        ownership.abandon(activity)
        check(fresh.closes == 1)
    }
    private fun successorDuringActualClose() {
        val first = Descriptor(); val second = Descriptor()
        val entered = CountDownLatch(1); val unblock = CountDownLatch(1)
        val ownership = readyOwnership(2) {
            if (it === first) { entered.countDown(); await(unblock) }
            it.close()
        }
        val activity = Any()
        ownership.register("first", activity, "owner", first)
        ownership.handoff("first", activity, "owner")
        ownership.register("second", activity, "owner", second)
        ownership.handoff("second", activity, "owner")
        ownership.beginRecovery("owner", "candidate-a")
        val oldFailure = AtomicReference<Throwable?>()
        val old = thread(isDaemon = true) {
            try { ownership.completeRecovery("candidate-a") } catch (error: Throwable) { oldFailure.set(error) }
        }
        var successor: Thread? = null
        val newFailure = AtomicReference<Throwable?>()
        try {
            await(entered)
            ownership.beginRecovery("candidate-a", "candidate-b")
            failure("usb_owner_stale") { ownership.completeRecovery("candidate-a") }
            val started = CountDownLatch(1)
            successor = thread(isDaemon = true) {
                started.countDown()
                try { ownership.completeRecovery("candidate-b") } catch (error: Throwable) { newFailure.set(error) }
            }
            await(started)
            check(ownership.environment()["ownerReady"] == false)
        } finally { unblock.countDown() }
        finish(old)
        finish(successor)
        check((oldFailure.get() as? UsbLeaseFailure)?.code == "usb_owner_stale")
        check(newFailure.get() == null) { "successor failed: ${newFailure.get()}" }
        check(first.closes == 1 && second.closes == 1)
        check(ownership.environment() == mapOf("ownerLeaseId" to "candidate-b", "ownerReady" to true))
    }
    private fun openingAndRegistrationAreAtomic() {
        val ownership = readyOwnership(1) { it.close() }
        val entered = CountDownLatch(1); val unblock = CountDownLatch(1)
        val attempted = CountDownLatch(1); val sealed = CountDownLatch(1)
        val activity = Any(); val descriptor = Descriptor()
        val openingError = AtomicReference<Throwable?>()
        val opening = thread(isDaemon = true) {
            try {
                check(ownership.open("opening", activity, "owner") {
                    entered.countDown(); await(unblock); descriptor
                } === descriptor)
            } catch (error: Throwable) { openingError.set(error) }
        }
        val sealingError = AtomicReference<Throwable?>()
        var sealing: Thread? = null
        try {
            await(entered)
            sealing = thread(isDaemon = true) {
                attempted.countDown()
                try { ownership.beginRecovery("owner", "next"); sealed.countDown() }
                catch (error: Throwable) { sealingError.set(error) }
            }
            await(attempted)
            check(!sealed.await(50, TimeUnit.MILLISECONDS))
            descriptor.assertOpen()
        } finally { unblock.countDown() }
        finish(opening)
        finish(sealing)
        check(openingError.get() == null && sealingError.get() == null)
        descriptor.assertOpen()
        failure("usb_recovery_pending") { ownership.handoff("opening", activity, "owner") }
        ownership.completeRecovery("next")
        check(descriptor.closes == 1)
    }
    private fun ordinaryReleaseFinishesBeforeSeal() {
        val entered = CountDownLatch(1); val unblock = CountDownLatch(1)
        val attempted = CountDownLatch(1); val sealed = CountDownLatch(1)
        val descriptor = Descriptor()
        val ownership = readyOwnership(1) { entered.countDown(); await(unblock); it.close() }
        val activity = Any()
        ownership.register("exact", activity, "owner", descriptor)
        ownership.handoff("exact", activity, "owner")
        val releaseError = AtomicReference<Throwable?>(); val sealError = AtomicReference<Throwable?>()
        val releasing = thread(isDaemon = true) {
            try { ownership.release("exact", "owner") } catch (error: Throwable) { releaseError.set(error) }
        }
        var sealing: Thread? = null
        try {
            await(entered)
            sealing = thread(isDaemon = true) {
                attempted.countDown()
                try { ownership.beginRecovery("owner", "next"); sealed.countDown() }
                catch (error: Throwable) { sealError.set(error) }
            }
            await(attempted)
            check(!sealed.await(50, TimeUnit.MILLISECONDS))
        } finally { unblock.countDown() }
        finish(releasing)
        finish(sealing)
        check(releaseError.get() == null && sealError.get() == null)
        check(descriptor.closes == 1)
        ownership.completeRecovery("next")
        check(descriptor.closes == 1)
    }
    private fun synchronousCloseReentryCannotCompleteSuccessor() {
        lateinit var ownership: UsbHandoffLeases<Descriptor>
        val descriptor = Descriptor()
        ownership = readyOwnership(1) {
            ownership.beginRecovery("candidate-a", "candidate-b")
            it.close()
        }
        val activity = Any()
        ownership.register("exact", activity, "owner", descriptor)
        ownership.handoff("exact", activity, "owner")
        ownership.beginRecovery("owner", "candidate-a")
        failure("usb_owner_stale") { ownership.completeRecovery("candidate-a") }
        check(descriptor.closes == 1)
        check(ownership.environment() == mapOf("ownerLeaseId" to "candidate-b", "ownerReady" to false))
        ownership.completeRecovery("candidate-b")
        check(ownership.environment()["ownerReady"] == true)
        check(descriptor.closes == 1)
    }

    private fun exactPermissionCancellationAfterSeal() {
        val ownership = readyOwnership(1) { it.close() }
        val requests = UsbPermissionRequests()
        var oldCancelled = 0; var nextCancelled = 0
        requests.begin("owner", "same-attempt") { oldCancelled++ }
        ownership.beginRecovery("owner", "next")
        // 封存不能允许普通 FD release，但旧 UI 的精确取消仍可结清。
        val oldToken = ownership.validateToken("owner")
        check(requests.cancel(oldToken, "same-attempt"))
        check(oldCancelled == 1 && requests.owner() == null)
        check(!requests.cancel(oldToken, "same-attempt"))
        ownership.completeRecovery("next")
        requests.begin("next", "same-attempt") { nextCancelled++ }
        check(!requests.cancel(oldToken, "same-attempt"))
        check(!requests.cancel("next", "different-attempt"))
        check(!requests.cancel("next", null))
        check(requests.owner() == "next" && nextCancelled == 0)
        check(requests.cancel("next", "same-attempt"))
        check(nextCancelled == 1)
        requests.begin("next", "throwing") { error("reply endpoint disappeared") }
        check(runCatching { requests.cancel("next", "throwing") }.isFailure)
        check(requests.owner() == null)
        check(!requests.cancel("next", "throwing"))
        requests.begin("next", "new") { nextCancelled++ }
        requests.clear() // Activity 销毁先摘除旧 UI，后继重新附着不继承其取消权。
        check(!requests.cancel("next", "new"))
        check(nextCancelled == 1)
    }

}
