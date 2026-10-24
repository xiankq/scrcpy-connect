package dev.scrcpyconnect.scrcpy_connect

import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 独立 JVM 所有权检查，不构造假文档提供方或 Android 界面。 */
object DocumentPickerReplyTest {
    private class Reply : MethodChannel.Result {
        val values = mutableListOf<Any?>()
        val errors = mutableListOf<String>()
        override fun success(value: Any?) {values.add(value)}
        override fun error(code: String, message: String?, details: Any?) {errors.add(code)}
        override fun notImplemented() {error("not_implemented", null, null)}
    }
    @JvmStatic fun main(args: Array<String>) {
        val cancelled = Reply()
        val pending = DocumentPickerReply(cancelled)
        pending.success(mapOf("status" to "cancelled"))
        // 取消后 Binder 工作线程仍可能成功完成或抛出异常。
        pending.success(mapOf("status" to "selected"))
        pending.error("late_provider", "late", null)
        check(cancelled.values == listOf(mapOf("status" to "cancelled")))
        check(cancelled.errors.isEmpty())
        val succeeded = Reply()
        val completed = DocumentPickerReply(succeeded)
        completed.success(mapOf("status" to "selected"))
        completed.success(mapOf("status" to "cancelled"))
        check(succeeded.values == listOf(mapOf("status" to "selected")))
        val rejected = Reply()
        val failed = DocumentPickerReply(rejected)
        failed.error("permission_denied", "denied", null)
        failed.success(mapOf("status" to "cancelled"))
        check(rejected.errors == listOf("permission_denied"))
        check(rejected.values.isEmpty())
        val completedDescriptor = mutableListOf<String>()
        DocumentDescriptorCompletion(
            checkError = {completedDescriptor.add("check")},
            close = {completedDescriptor.add("close")},
            closeWithError = {completedDescriptor.add("abort")}
        ).finish(success = true)
        check(completedDescriptor == listOf("check", "close", "check"))
        val abortedDescriptor = mutableListOf<String>()
        DocumentDescriptorCompletion(
            checkError = {abortedDescriptor.add("check")},
            close = {abortedDescriptor.add("close")},
            closeWithError = {abortedDescriptor.add("abort")}
        ).finish(success = false)
        check(abortedDescriptor == listOf("abort"))

        val failedDescriptor = mutableListOf<String>()
        val peerFailure = IllegalStateException("peer failed before close")
        val closeFailure = IllegalStateException("close failed")
        val finalFailure = IllegalStateException("peer failed during close")
        var checks = 0
        val reported = runCatching {
            DocumentDescriptorCompletion(
                checkError = {
                    failedDescriptor.add("check")
                    checks++
                    throw if (checks == 1) peerFailure else finalFailure
                },
                close = {failedDescriptor.add("close"); throw closeFailure},
                closeWithError = {error("success must still close after a peer error")}
            ).finish(success = true)
        }.exceptionOrNull()
        check(failedDescriptor == listOf("check", "close", "check")) {
            "A peer failure must not skip descriptor close or the final error check: $failedDescriptor"
        }
        check(reported === peerFailure)
        check(peerFailure.suppressed.toList() == listOf(closeFailure, finalFailure))
        // 接管开始即撤准入；丢失回执或新 isolate 只能按仍可发现的精确代次继续接管。
        val owner = DocumentPlatformOwner<DocumentDescriptorLease>()
        val firstActivity = Any()
        val nextActivity = Any()
        check(owner.attach(firstActivity))
        check(owner.claim(null, "first"))
        check(!owner.accepts("first"))
        check(owner.complete("first"))
        check(owner.accepts("first"))
        check(owner.claim("first", "pending"))
        check(owner.current() == "pending")
        check(!owner.accepts("first") && !owner.accepts("pending"))
        check(owner.claim("pending", "replacement"))
        check(!owner.complete("pending")) {"迟到清理不能开放已替换代次"}
        check(runCatching {owner.claim("first", "stale")}.isFailure)
        check(owner.complete("replacement"))
        check(owner.accepts("replacement"))
        check(!owner.claim("first", "replacement")) {"同一精确代次的确认重试应幂等"}
        check(!owner.accepts("first"))

        var retainedCloseAttempts = 0
        val retained = DocumentDescriptorLease(
            checkError = {}, close = {},
            closeWithError = {retainedCloseAttempts++; if (retainedCloseAttempts == 1) error("关闭尚未确认")}
        )
        owner.operations["original-pfd"] = retained
        check(owner.detach(firstActivity))
        check(!owner.accepts("replacement"))
        check(owner.current() == "replacement")
        check(owner.operations["original-pfd"] === retained && !retained.released)
        // 已经开始的工作迟到交付仍登记到同一进程 owner，不能落回被销毁 Activity。
        val late = DocumentDescriptorLease(checkError = {}, close = {}, closeWithError = {})
        owner.operations["late-pfd"] = late
        check(owner.attach(nextActivity))
        check(!owner.detach(firstActivity)) {"旧 Activity 不得撤销新附着"}
        check(owner.activity() === nextActivity)
        check(!owner.accepts("replacement")) {"重新附着不能提前开放准入"}
        check(!owner.complete("replacement")) {"旧 Activity 的迟到确认无权开放准入"}
        check(owner.permitsCleanup(nextActivity, "replacement", "replacement")) {
            "同 Dart 会话必须能经当前 Activity 收尾旧代次的精确操作"
        }
        check(!owner.permitsCleanup(firstActivity, "replacement", "replacement"))
        check(!owner.permitsCleanup(nextActivity, "replacement", "new-operation-lease"))
        check(owner.permitsCleanup(nextActivity, "replacement", null)) {"已移除操作的清理确认可幂等"}
        check(!owner.permitsCleanup(nextActivity, null, null))
        check(owner.claim("replacement", "recovered"))
        check(runCatching {retained.finish(false)}.isFailure)
        check(owner.operations["original-pfd"] === retained && !retained.released)
        check(!owner.accepts("recovered"))
        retained.finish(false)
        late.finish(false)
        owner.operations.entries.removeAll {it.value.released}
        check(owner.operations.isEmpty())
        check(owner.complete("recovered"))
        check(owner.accepts("recovered"))
        check(!owner.detach(firstActivity))
        check(owner.accepts("recovered"))

        // 关闭回执不能先于原始 PFD 真实关闭；失败保留所有权并允许同一租约重试。
        val closeEntered = CountDownLatch(1)
        val allowClose = CountDownLatch(1)
        val closeFinished = CountDownLatch(1)
        val blockingLease = DocumentDescriptorLease(
            checkError = {}, close = {},
            closeWithError = {closeEntered.countDown(); check(allowClose.await(5, TimeUnit.SECONDS))}
        )
        val closeThread = Thread {
            blockingLease.finish(false)
            closeFinished.countDown()
        }.also {it.start()}
        check(closeEntered.await(5, TimeUnit.SECONDS))
        check(!blockingLease.released)
        check(!closeFinished.await(30, TimeUnit.MILLISECONDS))
        allowClose.countDown()
        check(closeFinished.await(5, TimeUnit.SECONDS))
        closeThread.join(5000)
        check(blockingLease.released)
        var attempts = 0
        val retryLease = DocumentDescriptorLease(
            checkError = {}, close = {},
            closeWithError = {attempts++; if (attempts == 1) error("关闭失败")}
        )
        check(runCatching {retryLease.finish(false)}.isFailure)
        check(!retryLease.released)
        retryLease.finish(false)
        check(retryLease.released && attempts == 2)
        retryLease.finish(false)
        check(attempts == 2) {"已释放的精确描述符不得再次关闭"}

        // 提供方报错与物理关闭是两份事实：仍报告未知结果，但不遗留已关闭描述符。
        var physicalCloses = 0
        val erroredLease = DocumentDescriptorLease(
            checkError = {error("提供方回执未知")},
            close = {physicalCloses++}, closeWithError = {physicalCloses++}
        )
        check(runCatching {erroredLease.finish(true)}.isFailure)
        check(erroredLease.released && physicalCloses == 1)
        erroredLease.finish(false)
        check(physicalCloses == 1)
        println("PASS: picker once replies, descriptor close barriers/retry and owner generation takeover")
    }
}
