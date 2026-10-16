package dev.scrcpyconnect.scrcpy_connect

import java.io.File
import java.util.Properties
import java.util.UUID

internal data class SharedFile(val diskName: String, val name: String, val size: Long)
internal data class ShareTransfer(val id: String, val status: String, val sources: List<String>)
internal data class ShareLimits(val pending: Int = 8, val batches: Int = 64, val leases: Int = 128,
    val uris: Int = 32, val fileBytes: Long = 512L * 1024 * 1024,
    val batchBytes: Long = 1024L * 1024 * 1024, val totalBytes: Long = 2L * 1024 * 1024 * 1024,
    val timeoutMillis: Long = 120_000, val pendingExpiryMillis: Long = 24L * 60 * 60 * 1000,
    val references: Int = 1024, val sourcesPerReference: Int = 2048,
    val totalSourceEntries: Int = 8192, val sourcePathChars: Int = 4096)

/** Private, durable ownership journal. Only registered child files can be reclaimed.
 * Unknown/interrupted transfer leases survive process restart and never expire by time alone. */
internal class ShareImportPolicy(val root: File, val limits: ShareLimits = ShareLimits(),
    private val clock: () -> Long = System::currentTimeMillis) {
    private data class Batch(val id: String, val created: Long, var visible: Boolean, var status: String,
        var bytes: Long = 0, var text: String? = null, var mime: String? = null,
        var files: List<SharedFile> = emptyList(), var errors: List<String> = emptyList())
    private data class Lease(val id: String, val shareId: String, var transferId: String?)
    private val batches = linkedMapOf<String, Batch>()
    private val leases = linkedMapOf<String, Lease>()
    private var orphanBytes = 0L
    private var orphanBatches = 0
    private var journalUncertain = false
    init {
        root.mkdirs()
        for (directory in root.listFiles().orEmpty().filter { it.isDirectory && it.name != ".leases" }) {
            val metadata = File(directory, ".share")
            val batch = runCatching {
                require(validId(directory.name) && metadata.length() <= 8_388_608)
                val p = load(metadata)
                val count = p.getProperty("count", "0").toInt().also { require(it in 0..limits.uris) }
                val files = (0 until count).map { index ->
                    val disk = p.getProperty("file.$index.disk")
                    require(disk == File(disk).name && disk !in listOf(".", "..", ".share"))
                    val file = File(directory, disk)
                    require(file.isFile && file.canonicalFile.parentFile == directory.canonicalFile)
                    SharedFile(disk, p.getProperty("file.$index.name"), file.length())
                }
                Batch(directory.name, p.getProperty("created").toLong(), p.getProperty("visible") == "true",
                    p.getProperty("status"), files.sumOf { it.size }, p.getProperty("text"), p.getProperty("mime"), files,
                    listOfNotNull(p.getProperty("error")))
            }.getOrNull()
            if (batch == null) {
                // Never infer a transfer is terminal just because metadata was damaged.
                orphanBytes += directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }
                orphanBatches++
                continue
            }
            if (batch.status == "importing") {
                // No file list or retain operation was published before completion.
                directory.listFiles().orEmpty().filter { it.name != ".share" }.forEach { it.deleteRecursively() }
                batch.status = "error"; batch.bytes = 0; batch.files = emptyList()
                batch.errors = listOf("上次分享导入已中断，请重新分享。")
                persist(batch)
            }
            batches[batch.id] = batch
        }
        for (file in File(root, ".leases").listFiles().orEmpty()) if (runCatching {
            require(validId(file.name) && file.length() <= 16_384)
            val p = load(file); val share = p.getProperty("share")
            require(batches.containsKey(share))
            leases[file.name] = Lease(file.name, share, p.getProperty("transfer"))
        }.isFailure) journalUncertain = true
    }
    private fun validId(id: String) = runCatching { UUID.fromString(id).toString() == id }.getOrDefault(false)
    fun directory(id: String): File { require(validId(id)); return File(root, id) }
    private fun load(file: File) = Properties().apply { file.inputStream().use { load(it) } }
    private fun save(file: File, p: Properties) {
        file.parentFile!!.mkdirs()
        val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.outputStream().use { output -> p.store(output, "Private incoming-share ownership"); output.fd.sync() }
            check(temporary.renameTo(file)) { "无法保存分享来源记录。" }
        } finally { temporary.delete() }
    }
    private fun persist(batch: Batch) {
        val p = Properties(); p["created"] = batch.created.toString(); p["visible"] = batch.visible.toString()
        p["status"] = batch.status; p["count"] = batch.files.size.toString()
        batch.text?.let { p["text"] = it }; batch.mime?.let { p["mime"] = it }
        if (batch.errors.isNotEmpty()) p["error"] = batch.errors.joinToString("；").take(4096)
        batch.files.forEachIndexed { index, file -> p["file.$index.disk"] = file.diskName; p["file.$index.name"] = file.name }
        save(File(directory(batch.id), ".share"), p)
    }
    private fun persist(lease: Lease) {
        val p = Properties(); p["share"] = lease.shareId; lease.transferId?.let { p["transfer"] = it }
        save(File(root, ".leases/${lease.id}"), p)
    }
    @Synchronized fun reserve(id: String) {
        require(validId(id) && !batches.containsKey(id))
        check(batches.values.count { it.visible } < limits.pending && batches.size + orphanBatches < limits.batches) { "待处理或保留中的分享已满，请先处理现有内容。" }
        check(retainedBytes() < limits.totalBytes) { "分享暂存空间已满；已保留的任务来源不会被自动删除。" }
        val batch = Batch(id, clock(), true, "importing")
        persist(batch); batches[id] = batch
    }
    @Synchronized fun reserveBytes(id: String, count: Int) {
        val batch = batches[id] ?: error("分享导入已取消。")
        check(batch.visible && batch.status == "importing") { "分享导入已取消。" }
        check(count >= 0 && batch.bytes + count <= limits.batchBytes && retainedBytes() + count <= limits.totalBytes) { "分享内容超过本批或总暂存容量；已有任务来源保持不变。" }
        check(root.usableSpace - count >= 32L * 1024 * 1024) { "本机可用空间不足，未继续写入分享缓存。" }
        batch.bytes += count
    }
    @Synchronized fun complete(id: String, text: String?, mime: String?, files: List<SharedFile>): Map<String, Any?>? {
        val batch = batches[id] ?: return null
        if (!batch.visible || batch.status != "importing") return null
        val published = batch.copy(text = text, mime = mime, files = files, status = "ready")
        persist(published); batches[id] = published; return view(published)
    }
    @Synchronized fun fail(id: String, message: String): Map<String, Any?>? {
        val batch = batches[id] ?: return null
        if (batch.status != "importing") return null
        directory(id).deleteRecursively(); batch.bytes = 0; batch.files = emptyList(); batch.status = "error"
        batch.errors = listOf(message.take(4096)); persist(batch); return view(batch)
    }
    @Synchronized fun cleanupAborted(id: String) {
        val batch = batches[id]
        if (batch == null) directory(id).deleteRecursively()
        else if (batch.status == "error") directory(id).listFiles().orEmpty().filter { it.name != ".share" }.forEach { it.deleteRecursively() }
    }
    @Synchronized fun consume(id: String) {
        val batch = batches[id] ?: return
        batch.visible = false; persist(batch); reclaim(batch)
    }
    @Synchronized fun retain(id: String): Map<String, Any?> {
        leases.values.find { it.shareId == id }?.let { return leaseView(it) }
        val batch = batches[id] ?: error("分享来源已不存在。")
        check(batch.status == "ready" && batch.files.isNotEmpty()) { "分享文件尚未导入完成。" }
        check(leases.size < limits.leases) { "保留中的分享任务过多，请先处理现有任务。" }
        val lease = Lease(UUID.randomUUID().toString(), id, null)
        persist(lease); leases[lease.id] = lease; return leaseView(lease)
    }
    @Synchronized fun bind(leaseId: String, transferId: String): Map<String, Any?> {
        require(validId(transferId)) { "传输标识无效。" }
        val lease = leases[leaseId] ?: error("分享租约已不存在。")
        check(lease.transferId == null || lease.transferId == transferId) { "分享租约已属于另一项任务。" }
        val previous = lease.transferId
        lease.transferId = transferId
        try { persist(lease) } catch (error: Exception) { lease.transferId = previous; throw error }
        return leaseView(lease)
    }
    @Synchronized fun release(leaseId: String) {
        val lease = leases[leaseId] ?: return
        val journal = File(root, ".leases/$leaseId")
        check(!journal.exists() || journal.delete()) { "未能更新分享租约；任务来源仍保留。" }
        leases.remove(leaseId)
        batches[lease.shareId]?.let { reclaim(it) }
    }
    private fun reclaim(batch: Batch) {
        if (!journalUncertain && !batch.visible && leases.values.none { it.shareId == batch.id }) {
            check(directory(batch.id).deleteRecursively()) { "未能清理分享暂存；来源仍保留。" }
            batches.remove(batch.id)
        }
    }
    /** A bounded source inventory, not a statement that the caller's task snapshot is complete. */
    @Synchronized fun sources(): Map<String, Any?> = mapOf(
        "sourcePaths" to batches.values.flatMap { paths(it) }, "leases" to leases.values.map(::leaseView),
        "limits" to mapOf("references" to limits.references, "sourcesPerReference" to limits.sourcesPerReference,
            "totalSourceEntries" to limits.totalSourceEntries, "sourcePathChars" to limits.sourcePathChars))

    /** Parse platform data only after admission. Never truncate and then trust `complete`. */
    @Synchronized fun reconcileInput(input: List<*>, complete: Boolean): Map<String, Any?> {
        if (input.size > limits.references) return snapshot(false, false, "reference_limit")
        val transfers = ArrayList<ShareTransfer>(input.size)
        var entries = 0
        for (raw in input) {
            val row = raw as? Map<*, *> ?: return snapshot(false, false, "invalid_snapshot")
            val id = row["id"] as? String ?: return snapshot(false, false, "invalid_snapshot")
            val status = row["status"] as? String ?: return snapshot(false, false, "invalid_snapshot")
            val sources = row["sources"] as? List<*> ?: return snapshot(false, false, "invalid_snapshot")
            if (sources.size > limits.sourcesPerReference || entries + sources.size > limits.totalSourceEntries)
                return snapshot(false, false, "reference_limit")
            if (id.length > 128 || status.length > 64 || sources.any { it !is String || it.length > limits.sourcePathChars })
                return snapshot(false, false, "invalid_snapshot")
            entries += sources.size
            transfers.add(ShareTransfer(id, status, sources.map { it as String }))
        }
        return reconcile(transfers, complete)
    }
    @Synchronized fun reconcile(transfers: List<ShareTransfer>, complete: Boolean): Map<String, Any?> {
        // Direct callers use the same all-or-nothing boundary as the MethodChannel parser.
        if (transfers.size > limits.references) return snapshot(false, false, "reference_limit")
        var entries = 0
        for (transfer in transfers) {
            if (transfer.sources.size > limits.sourcesPerReference || entries + transfer.sources.size > limits.totalSourceEntries)
                return snapshot(false, false, "reference_limit")
            if (transfer.id.length > 128 || transfer.status.length > 64 || transfer.sources.any { it.length > limits.sourcePathChars })
                return snapshot(false, false, "invalid_snapshot")
            entries += transfer.sources.size
        }
        val registered = batches.values.flatMap { paths(it) }.toSet()
        val bySource = linkedMapOf<String, MutableList<ShareTransfer>>()
        for (transfer in transfers) for (path in transfer.sources) {
            // Never traverse or delete a caller-provided path. Match exact registered paths only.
            if (path in registered) bySource.getOrPut(path) { mutableListOf() }.add(transfer)
        }
        val verifiedComplete = complete && transfers.none { it.sources.isEmpty() }
        for (lease in leases.values.toList()) {
            val batch = batches[lease.shareId] ?: continue
            val matched = paths(batch).flatMap { bySource[it].orEmpty() }.distinctBy { it.id }
            if (lease.transferId == null && matched.size == 1 && validId(matched[0].id)) {
                bind(lease.id, matched[0].id)
            }
            if (verifiedComplete && lease.transferId != null && transfers.any { it.id == lease.transferId && it.status == "completed" && paths(batch).all { source -> source in it.sources } }
                && matched.none { it.status != "completed" }) release(lease.id)
        }
        if (verifiedComplete) for (batch in batches.values.toList()) {
            if (clock() - batch.created > limits.pendingExpiryMillis && batch.status != "importing"
                && leases.values.none { it.shareId == batch.id } && paths(batch).none { bySource.containsKey(it) }) {
                batch.visible = false; reclaim(batch)
            }
        }
        return snapshot(true, verifiedComplete, if (verifiedComplete) null else "incomplete_snapshot")
    }
    private fun snapshot(reconciled: Boolean, complete: Boolean, reason: String?): Map<String, Any?> = mapOf(
        "reconciled" to reconciled, "snapshotComplete" to complete, "reason" to reason,
        "leases" to leases.values.map(::leaseView), "retainedBytes" to retainedBytes(), "unknownBytes" to orphanBytes,
        "needsReview" to (journalUncertain || orphanBatches > 0), "unknownBatches" to orphanBatches)
    private fun paths(batch: Batch) = batch.files.map { File(directory(batch.id), it.diskName).absolutePath }
    private fun view(batch: Batch): Map<String, Any?> = mapOf("shareId" to batch.id, "status" to batch.status,
        "text" to batch.text, "mime" to batch.mime, "files" to batch.files.map { mapOf("name" to it.name, "size" to it.size,
            "localPath" to File(directory(batch.id), it.diskName).absolutePath) }, "errors" to batch.errors)
    private fun leaseView(lease: Lease): Map<String, Any?> = mapOf("leaseId" to lease.id, "shareId" to lease.shareId,
        "transferId" to lease.transferId, "status" to if (lease.transferId == null) "unknown" else "bound",
        "files" to batches[lease.shareId]?.let { view(it)["files"] })
    @Synchronized fun pending() = batches.values.filter { it.visible }.map(::view)
    @Synchronized fun retainedBytes(): Long = orphanBytes + batches.values.sumOf { it.bytes }
}
