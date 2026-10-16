package dev.scrcpyconnect.scrcpy_connect

import java.io.File
import java.nio.file.Files
import java.util.UUID

object NativeOwnershipTest {
    private fun id() = UUID.randomUUID().toString()
    private fun ready(policy: ShareImportPolicy, text: String = "fixture"): Pair<String, File> {
        val id = id(); policy.reserve(id)
        val file = File(policy.directory(id), "0-fixture.txt"); file.writeText(text)
        policy.reserveBytes(id, file.length().toInt())
        check(policy.complete(id, null, "text/plain", listOf(SharedFile(file.name, "测试文件.txt", file.length()))) != null)
        return id to file
    }
    @JvmStatic fun main(args: Array<String>) {
        val root = Files.createTempDirectory("interop-share-contracts-").toFile()
        try {
            queueAndBytesBoundBeforePublication(File(root, "bounds"))
            leaseSurvivesConsumeRestartAndOnlyConfirmedCompletionReclaims(File(root, "restart"))
            unknownAndOtherTaskReferencesSurvive(File(root, "unknown"))
            cancelledImportsAndLateTimeoutNeverDeletePublishedLease(File(root, "cancel"))
            journalFailurePreservesOwnership(File(root, "journal-failure"))
            activityRebindingDoesNotReplaceAudio()
            println("PASS: 6 native ownership contracts: bounded admission, durable lease, conservative reconcile, cancel/late deadline, journal failure, same-process audio lifecycle")
        } finally { root.deleteRecursively() }
    }
    private fun queueAndBytesBoundBeforePublication(root: File) {
        val policy = ShareImportPolicy(root, ShareLimits(pending = 2, batchBytes = 10, totalBytes = 12))
        val first = id(); val second = id(); val overflow = id()
        policy.reserve(first); policy.reserve(second)
        check(runCatching { policy.reserve(overflow) }.isFailure)
        check(!policy.directory(overflow).exists())
        policy.reserveBytes(first, 8)
        check(runCatching { policy.reserveBytes(first, 3) }.isFailure)
        check(runCatching { policy.reserveBytes(second, 5) }.isFailure)
        policy.fail(first, "fixture failed")
        check(policy.retainedBytes() == 0L)
        policy.consume(first); check(!policy.directory(first).exists())
        policy.reserve(overflow)
    }
    private fun leaseSurvivesConsumeRestartAndOnlyConfirmedCompletionReclaims(root: File) {
        var now = 1000L
        var policy = ShareImportPolicy(root, clock = { now })
        val (share, file) = ready(policy)
        val lease = policy.retain(share)["leaseId"] as String
        check(policy.retain(share)["leaseId"] == lease)
        policy.consume(share); check(file.readText() == "fixture")
        policy = ShareImportPolicy(root, clock = { now })
        val transfer = id()
        var snapshot = policy.reconcile(listOf(ShareTransfer(transfer, "failed", listOf(file.absolutePath))), true)
        val restored = (snapshot["leases"] as List<*>).single() as Map<*, *>
        check(restored["leaseId"] == lease && restored["transferId"] == transfer)
        now += 30L * 24 * 60 * 60 * 1000
        policy.reconcile(emptyList(), true); check(file.exists()) // missing task is unknown, not terminal
        policy.reconcile(listOf(ShareTransfer(transfer, "cancelled", listOf(file.absolutePath))), true); check(file.exists())
        snapshot = policy.reconcile(listOf(ShareTransfer(transfer, "completed", listOf(file.absolutePath))), true)
        check((snapshot["leases"] as List<*>).isEmpty()); check(!file.exists())
    }
    private fun unknownAndOtherTaskReferencesSurvive(root: File) {
        val policy = ShareImportPolicy(root)
        val (share, file) = ready(policy)
        val lease = policy.retain(share)["leaseId"] as String
        val first = id(); val other = id()
        policy.bind(lease, first); policy.consume(share)
        policy.reconcile(listOf(ShareTransfer(first, "completed", listOf(file.absolutePath)), ShareTransfer(other, "running", listOf(file.absolutePath))), true)
        check(file.exists())
        val outside = File(root.parentFile, "outside-sentinel"); outside.writeText("do not delete")
        policy.reconcile(listOf(ShareTransfer(first, "unknown", listOf(outside.absolutePath))), true)
        check(outside.readText() == "do not delete" && file.exists())
        policy.reconcile(listOf(ShareTransfer(first, "completed", emptyList())), true)
        check(file.exists()) // missing source paths are not proof of completion ownership
        policy.reconcile(listOf(ShareTransfer(first, "completed", listOf(file.absolutePath))), false)
        check(file.exists()) // incomplete snapshots never authorize reclamation
    }
    private fun cancelledImportsAndLateTimeoutNeverDeletePublishedLease(root: File) {
        val policy = ShareImportPolicy(root)
        val (share, file) = ready(policy)
        val lease = policy.retain(share)["leaseId"] as String
        check(policy.fail(share, "late deadline") == null)
        check(file.exists())
        policy.consume(share); check(file.exists()); policy.release(lease); check(!file.exists())
        val cancelled = id(); policy.reserve(cancelled); policy.consume(cancelled)
        policy.directory(cancelled).mkdirs(); File(policy.directory(cancelled), "late-partial").writeText("partial")
        check(policy.complete(cancelled, null, null, emptyList()) == null)
        policy.cleanupAborted(cancelled); check(!policy.directory(cancelled).exists())
        val interrupted = id(); policy.reserve(interrupted)
        File(policy.directory(interrupted), "partial").writeText("partial")
        val restored = ShareImportPolicy(root)
        check(!File(restored.directory(interrupted), "partial").exists())
        check(restored.pending().any { it["shareId"] == interrupted && it["status"] == "error" })
    }
    private class Audio : OwnedAudio {
        var closed = 0; var paused = false; var revision = 0L
        override fun background(paused: Boolean): Map<String, Any?> { this.paused = paused; revision++; return status() }
        override fun status() = mapOf("sourceId" to "same-source", "applied" to true, "revision" to revision, "playState" to if (paused) "paused" else "playing")
        override fun close() { closed++ }
    }
    private fun journalFailurePreservesOwnership(root: File) {
        val policy = ShareImportPolicy(root)
        val (share, file) = ready(policy)
        val lease = policy.retain(share)["leaseId"] as String
        val journal = File(root, ".leases/$lease")
        check(journal.delete()); check(journal.mkdir())
        File(journal, "filesystem-error-fixture").writeText("prevent deletion")
        policy.consume(share)
        check(runCatching { policy.release(lease) }.isFailure)
        check(file.exists() && policy.retain(share)["leaseId"] == lease)
        check(runCatching { policy.bind(lease, id()) }.isFailure)
        check(policy.retain(share)["transferId"] == null)
        val second = id(); policy.reserve(second)
        val metadata = File(policy.directory(second), ".share")
        check(metadata.delete()); check(metadata.mkdir())
        File(metadata, "filesystem-error-fixture").writeText("prevent replacement")
        check(runCatching { policy.complete(second, null, null, emptyList()) }.isFailure)
        check(policy.pending().any { it["shareId"] == second && it["status"] == "importing" })
        policy.fail(second, "journal error"); check(policy.pending().any { it["shareId"] == second && it["status"] == "error" })
    }
    private fun activityRebindingDoesNotReplaceAudio() {
        val receipts = mutableListOf<Map<String, Any?>>()
        val owner = AudioSessionOwnership { receipts.add(it) }
        val oldActivity = Any(); val newActivity = Any(); val audio = Audio()
        owner.setVisible(oldActivity, true); owner.add("same-source", audio)
        owner.setVisible(oldActivity, false); check(audio.paused && audio.closed == 0)
        owner.setVisible(newActivity, true); check(!audio.paused && owner.get("same-source") === audio)
        owner.backgroundAllowed = true
        owner.setVisible(newActivity, false); check(!audio.paused && audio.closed == 0)
        owner.setVisible(Any(), false); check(!audio.paused) // late detach cannot stop shared owner
        check(owner.snapshots().single()["sourceId"] == "same-source")
        owner.stopAll(); owner.stopAll(); check(audio.closed == 1 && owner.empty())
    }
}
