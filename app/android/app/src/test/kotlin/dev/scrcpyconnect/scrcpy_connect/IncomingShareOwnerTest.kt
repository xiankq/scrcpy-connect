package dev.scrcpyconnect.scrcpy_connect

import java.io.File
import java.io.FileInputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** 使用生产登记与真实文件描述符验证，不以 Activity stub 的回执冒充关闭。 */
object IncomingShareOwnerTest {
    private class Source(val stream: FileInputStream, var failClose: Boolean = false)
    @JvmStatic fun main(args: Array<String>) {
        val path = File.createTempFile("incoming-share-owner-", ".bin")
        path.writeBytes(byteArrayOf(1, 2, 3))
        val closes = AtomicInteger()
        val owner = IncomingShareOwner<Source>({source ->
            closes.incrementAndGet()
            if (source.failClose) error("原始描述符关闭失败")
            source.stream.close()
        }, capacity = 4, openingCapacity = 2)
        val first = Any()
        val second = Any()
        var cancelled = 0
        try {
            owner.attach(first)
            check(!owner.accepts(null))
            check(runCatching {owner.register(first, "old", "open", "fd") {}}.isFailure)
            check(owner.claim(first, null, "old")!!.isEmpty())
            check(owner.complete(first, "old"))
            val old = owner.register(first, "old", "same-open", "old-fd") {cancelled++}
            val original = Source(FileInputStream(path))
            old.opened(original)
            old.finished.complete(Unit)
            check(owner.detach(first) == listOf(old))
            check(!owner.accepts("old"))
            check(original.stream.fd.valid()) {"Activity 分离不能关闭可能仍由 SDK 读取的原始 PFD"}
            check(closes.get() == 0)
            owner.attach(second).forEach {it.cancel()}
            check(cancelled == 1)
            check(owner.detach(first).isEmpty())
            check(owner.current(second))
            check(owner.byOpen(second, "old", "same-open") == listOf(old))
            check(runCatching {owner.byDescriptor(first, "old", "old-fd")}.isFailure)
            check(runCatching {owner.byDescriptor(second, "wrong", "old-fd")}.isFailure)
            val retired = owner.claim(second, "old", "recovered")!!
            check(retired == listOf(old))
            check(!owner.complete(second, "recovered"))
            old.drain()
            check(!original.stream.fd.valid())
            owner.forget(old)
            check(owner.complete(second, "recovered"))
            // 已提交但 Dart 丢回执，同候选只确认，不能再次关闭或改变 ready。
            check(owner.claim(second, "old", "recovered") == null)
            check(owner.accepts("recovered"))
            val fresh = owner.register(second, "recovered", "same-open", "new-fd") {}
            check(owner.byOpen(second, "old", "same-open").isEmpty()) {"旧 openId 清理不得命中新代次同名打开"}
            check(runCatching {owner.byDescriptor(second, "old", "new-fd")}.isFailure)

            // 取消回执必须等待真实 worker 的迟到交付，再关闭同一个描述符。
            val draining = CountDownLatch(1)
            val drained = CountDownLatch(1)
            fresh.cancel()
            val drainFailure = AtomicReference<Throwable?>()
            val drainThread = Thread {
                draining.countDown()
                try {fresh.drain()} catch (error: Throwable) {drainFailure.set(error)}
                finally {drained.countDown()}
            }.also {it.start()}
            check(draining.await(5, TimeUnit.SECONDS))
            check(!drained.await(30, TimeUnit.MILLISECONDS))
            val late = Source(FileInputStream(path), failClose = true)
            fresh.opened(late)
            // 第一次失败不能丢登记；同步调用复核后，由原线程作成功重试。
            fresh.finished.complete(Unit)
            check(drained.await(5, TimeUnit.SECONDS))
            drainThread.join(5000)
            check(drainFailure.get()?.message == "原始描述符关闭失败")
            check(!fresh.released && late.stream.fd.valid())
            check(owner.byDescriptor(second, "recovered", "new-fd") == listOf(fresh))
            late.failClose = false
            fresh.drain()
            owner.forget(fresh)
            check(!late.stream.fd.valid())
            val before = closes.get()
            fresh.drain()
            check(closes.get() == before) {"已关闭精确资源必须幂等"}

            // Activity 换代和另一候选可以撤旧确认，但不能开放存在未排空资源的代次。
            check(owner.claim(second, "recovered", "pending")!!.isEmpty())
            owner.attach(first)
            check(!owner.complete(second, "pending"))
            check(!owner.accepts("pending"))
            check(owner.claim(first, "pending", "newest")!!.isEmpty())
            check(!owner.complete(first, "pending"))
            check(runCatching {owner.claim(second, "pending", "stale")}.isFailure)
            check(owner.complete(first, "newest"))
            check(owner.detach(second).isEmpty() && owner.accepts("newest"))
            println("PASS: incoming share process owner, exact generation cleanup, late descriptor drain and close retry")
        } finally {path.delete()}
    }
}
