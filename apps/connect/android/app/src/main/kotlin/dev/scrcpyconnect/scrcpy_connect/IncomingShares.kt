package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.OpenableColumns
import java.io.Closeable
import java.io.File
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** OS-authorized foreign providers only; jobs never retain an Activity. */
object IncomingShares {
    private val main = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8)) { task -> Thread(task, "interop-share-import") }
    private val deadlines = Executors.newSingleThreadScheduledExecutor { task -> Thread(task, "interop-share-deadline") }
    // Provider Binder cancellation/close may itself block. Neither the UI nor the deadline
    // scheduler waits for it, and a hostile provider cannot create unbounded cancel threads.
    private val cancellations = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8)) { task -> Thread(task, "interop-share-cancel") }
    private var policy: ShareImportPolicy? = null
    private var observer: Any? = null
    private var deliver: ((Map<String, Any?>) -> Unit)? = null
    private var rejection: Map<String, Any?>? = null
    private class Job {
        val cancelled = AtomicBoolean(false)
        val signal = CancellationSignal()
        @Volatile var stream: Closeable? = null
        fun cancel() {
            if (!cancelled.compareAndSet(false, true)) return
            try {
                cancellations.execute {
                    try { signal.cancel() } finally { runCatching { stream?.close() } }
                }
            } catch (_: RejectedExecutionException) {
                // Still cancelled: no later read may publish or write another chunk. The
                // bounded provider worker can remain blocked until the provider returns.
            }
        }
        fun check() { check(!cancelled.get() && !Thread.currentThread().isInterrupted) { "分享导入已取消或超时。" } }
    }
    private val jobs = ConcurrentHashMap<String, Job>()
    @Synchronized private fun policy(context: Context): ShareImportPolicy = policy ?: ShareImportPolicy(File(context.applicationContext.cacheDir, "incoming")).also { policy = it }
    @Synchronized fun bind(owner: Any, callback: (Map<String, Any?>) -> Unit) { observer = owner; deliver = callback }
    @Synchronized fun unbind(owner: Any) { if (observer === owner) { observer = null; deliver = null } }
    private fun publish(share: Map<String, Any?>) { main.post { synchronized(this) { deliver }?.invoke(share) } }
    @Synchronized fun all(context: Context): List<Map<String, Any?>> = policy(context).pending() + listOfNotNull(rejection)
    @Synchronized fun consume(context: Context, id: String) {
        if (rejection?.get("shareId") == id) rejection = null
        jobs[id]?.cancel(); policy(context).consume(id)
    }
    fun retain(context: Context, id: String) = policy(context).retain(id)
    fun bindLease(context: Context, lease: String, transfer: String) = policy(context).bind(lease, transfer)
    fun release(context: Context, lease: String) { policy(context).release(lease) }
    fun sources(context: Context) = policy(context).sources()
    internal fun reconcile(context: Context, transfers: List<*>, complete: Boolean) = policy(context).reconcileInput(transfers, complete)
    private fun reject(id: String, reason: String) {
        val event = mapOf("shareId" to id, "status" to "error", "files" to emptyList<Any>(), "errors" to listOf(reason))
        synchronized(this) { rejection = event }; publish(event)
    }

    fun accept(context: Context, intent: Intent?, callerAllows: (Uri) -> Boolean = { true }) {
        if (intent == null || intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        val app = context.applicationContext
        val id = UUID.randomUUID().toString()
        val store = policy(app)
        try {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            require(text == null || text.length <= 1_048_576) { "分享的文字超过 1 MiB，请减少内容后重试。" }
            @Suppress("DEPRECATION")
            val streams: List<Uri> = if (intent.action == Intent.ACTION_SEND_MULTIPLE)
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            val clip = intent.clipData
            require(streams.size <= store.limits.uris && (clip?.itemCount ?: 0) <= store.limits.uris) { "一次最多分享 32 个内容文件。" }
            val uris = streams.ifEmpty { clip?.let { (0 until it.itemCount).mapNotNull { index -> it.getItemAt(index).uri } }.orEmpty() }.distinct()
            for (uri in uris) {
                require(uri.scheme == "content" && !uri.authority.isNullOrBlank()) { "只接受系统授权的内容文件。" }
                val provider = app.packageManager.resolveContentProvider(uri.authority!!, 0) ?: error("无法核实此内容提供方。")
                require(provider.packageName != app.packageName && provider.applicationInfo.uid != Process.myUid()) { "不能通过外部分享读取本应用的私有内容。" }
                require(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0 &&
                    app.checkUriPermission(uri, Process.myPid(), Process.myUid(), Intent.FLAG_GRANT_READ_URI_PERMISSION) == PackageManager.PERMISSION_GRANTED && callerAllows(uri)) { "分享未提供有效的内容读取授权。" }
            }
            store.reserve(id)
            val mime = intent.type
            intent.action = Intent.ACTION_MAIN
            val job = Job(); jobs[id] = job
            val deadline = deadlines.schedule({
                job.cancel()
                store.fail(id, "分享导入超时，未发布部分文件。")?.let(::publish)
            }, store.limits.timeoutMillis, TimeUnit.MILLISECONDS)
            try {
                worker.execute {
                    try {
                        val files = mutableListOf<SharedFile>()
                        for ((index, uri) in uris.withIndex()) {
                            job.check()
                            var name = "共享文件-" + (index + 1)
                            app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null, job.signal)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                    val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                                    if (nameColumn >= 0 && !cursor.isNull(nameColumn)) name = cursor.getString(nameColumn)
                                    if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) require(cursor.getLong(sizeColumn) <= store.limits.fileBytes) { "单个共享文件超过 512 MiB。" }
                                }
                            }
                            name = name.substringAfterLast('/').substringAfterLast('\\').replace('\u0000', '_').take(180).ifBlank { "共享文件-" + (index + 1) }
                            job.check()
                            val disk = "$index-${UUID.randomUUID()}"
                            val destination = File(store.directory(id), disk)
                            var size = 0L
                            app.contentResolver.openAssetFileDescriptor(uri, "r", job.signal)?.use { descriptor ->
                                descriptor.createInputStream().use { input ->
                                    job.stream = input; job.check()
                                    destination.outputStream().use { output ->
                                        val buffer = ByteArray(64 * 1024)
                                        while (true) {
                                            job.check(); val count = input.read(buffer); job.check()
                                            if (count < 0) break
                                            size += count
                                            require(size <= store.limits.fileBytes) { "单个共享文件超过 512 MiB。" }
                                            store.reserveBytes(id, count); output.write(buffer, 0, count)
                                        }
                                        output.fd.sync()
                                    }
                                    job.stream = null
                                }
                            } ?: error("系统未能读取此共享文件。")
                            files.add(SharedFile(disk, name, size))
                        }
                        job.check(); store.complete(id, text, mime, files)?.let(::publish)
                    } catch (error: Exception) {
                        store.fail(id, if (job.cancelled.get()) "分享导入已取消或超时。" else error.message ?: "读取分享失败。")?.let(::publish)
                    } finally { deadline.cancel(false); job.stream = null; jobs.remove(id, job); store.cleanupAborted(id); Thread.interrupted() }
                }
            } catch (error: Exception) {
                deadline.cancel(false); jobs.remove(id); job.cancel()
                store.fail(id, "分享导入队列已满，请稍后重新分享。")?.let(::publish)
            }
        } catch (error: Exception) {
            intent.action = Intent.ACTION_MAIN
            reject(id, error.message ?: "未能接收分享。")
        }
    }
}
