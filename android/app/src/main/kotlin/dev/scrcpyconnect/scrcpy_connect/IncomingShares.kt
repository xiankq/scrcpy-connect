package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.AssetFileDescriptor
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Permission and URI adapter; Rust owns imports, byte limits, journals and task leases. */
object IncomingShares {
    private data class Pending(val id: String, val text: String?, val mime: String?, val uris: List<Uri>) {
        fun view() = mapOf("shareId" to id, "text" to text, "mime" to mime, "sourceCount" to uris.size)
    }
    private data class FdLease(val owner: Any, val openId: String, val descriptor: AssetFileDescriptor)
    private class Open(val owner: Any, var reply: MethodChannel.Result?) {
        val signal = CancellationSignal()
        @Volatile var cancelled = false
    }
    private val main = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8)) { Thread(it, "interop-uri-open") }
    private val canceller = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8)) { Thread(it, "interop-uri-cancel") }
    private val pending = linkedMapOf<String, Pending>()
    private val descriptors = linkedMapOf<String, FdLease>()
    private val opening = linkedMapOf<String, Open>()
    private var rejection: Map<String, Any?>? = null
    private var observer: Any? = null
    private var deliver: ((Map<String, Any?>) -> Unit)? = null
    @Synchronized fun bind(owner: Any, callback: (Map<String, Any?>) -> Unit) { observer = owner; deliver = callback }
    @Synchronized fun unbind(owner: Any) { if (observer === owner) { observer = null; deliver = null } }
    @Synchronized fun releaseOwner(owner: Any) {
        opening.values.filter { it.owner === owner }.forEach { cancel(it); it.reply = null }
        descriptors.entries.filter { it.value.owner === owner }.toList().forEach { (id, _) -> release(id) }
        unbind(owner)
    }
    private fun publish(payload: Map<String, Any?>) { main.post { synchronized(this) { deliver }?.invoke(payload) } }
    private fun cancel(job: Open) {
        job.cancelled = true
        val reply = job.reply
        job.reply = null
        reply?.error("cancelled", "已取消打开分享来源。", null)
        try { canceller.execute { runCatching { job.signal.cancel() } } } catch (_: RejectedExecutionException) { }
    }
    @Synchronized private fun release(id: String) { descriptors.remove(id)?.descriptor?.close() }
    fun accept(context: Context, intent: Intent?, callerAllows: (Uri) -> Boolean = { true }) {
        if (intent == null || intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        val id = UUID.randomUUID().toString()
        try {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            require(text == null || text.length <= 1_048_576) { "分享的文字超过 1 MiB。" }
            @Suppress("DEPRECATION")
            val streams: List<Uri> = if (intent.action == Intent.ACTION_SEND_MULTIPLE)
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            val clip = intent.clipData
            require(streams.size <= 32 && (clip?.itemCount ?: 0) <= 32) { "一次最多分享 32 个文件。" }
            val uris = streams.ifEmpty { clip?.let { (0 until it.itemCount).mapNotNull { index -> it.getItemAt(index).uri } }.orEmpty() }.distinct()
            for (uri in uris) {
                require(uri.scheme == "content" && !uri.authority.isNullOrBlank()) { "只接受系统授权的内容文件。" }
                val provider = context.packageManager.resolveContentProvider(uri.authority!!, 0) ?: error("无法核实内容提供方。")
                require(provider.packageName != context.packageName && provider.applicationInfo.uid != Process.myUid()) { "不能通过外部分享读取本应用的私有内容。" }
                require(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0 &&
                    context.checkUriPermission(uri, Process.myPid(), Process.myUid(), Intent.FLAG_GRANT_READ_URI_PERMISSION) == PackageManager.PERMISSION_GRANTED && callerAllows(uri)) { "分享未提供有效的内容读取授权。" }
            }
            val item = Pending(id, text, intent.type, uris)
            synchronized(this) { check(pending.size < 8) { "待处理的分享已满。" }; pending[id] = item }
            publish(item.view())
        } catch (error: Exception) {
            val payload = mapOf("shareId" to id, "status" to "error", "files" to emptyList<Any>(), "errors" to listOf(error.message ?: "系统未授权读取分享。"))
            synchronized(this) { rejection = payload }; publish(payload)
        } finally { intent.action = Intent.ACTION_MAIN }
    }
    fun handle(context: Context, owner: Any, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "sharing.platform.environment" -> result.success(mapOf("cacheDirectory" to context.cacheDir.absolutePath))
            "sharing.platform.pending" -> result.success(synchronized(this) { mapOf("shares" to pending.values.map { it.view() } + listOfNotNull(rejection)) })
            "sharing.platform.consume" -> {
                val id = call.argument<String>("shareId")
                synchronized(this) { pending.remove(id); if (rejection?.get("shareId") == id) rejection = null }
                result.success(null)
            }
            "sharing.platform.release" -> { call.argument<String>("fdLeaseId")?.let { release(it) }; result.success(null) }
            "sharing.platform.cancel" -> {
                val id = call.argument<String>("openId")
                synchronized(this) {
                    opening[id]?.let { cancel(it) }
                    descriptors.entries.filter { it.value.openId == id }.toList().forEach { (lease, _) -> release(lease) }
                }
                result.success(null)
            }
            "sharing.platform.open" -> open(context.applicationContext, owner, call, result)
            else -> return false
        }
        return true
    }
    private fun open(context: Context, owner: Any, call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("openId") ?: error("Missing URI open id")
        val item = synchronized(this) { pending[call.argument<String>("shareId")] } ?: error("分享授权已失效，请重新分享。")
        val index = call.argument<Number>("index")?.toInt() ?: error("Missing URI index")
        val uri = item.uris.getOrNull(index) ?: error("分享文件不存在。")
        val job = Open(owner, result)
        synchronized(this) { check(opening.size < 8 && descriptors.size < 256 && !opening.containsKey(id)); opening[id] = job }
        try { worker.execute {
            var descriptor: AssetFileDescriptor? = null
            try {
                var name = "共享文件-${index + 1}"
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, job.signal)?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
                }
                check(!job.cancelled)
                descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r", job.signal) ?: error("系统未能打开此文件。")
                val opened = descriptor!!
                main.post { synchronized(this) {
                    opening.remove(id)
                    val reply = job.reply; job.reply = null
                    if (job.cancelled || reply == null) { opened.close(); return@synchronized }
                    val lease = UUID.randomUUID().toString()
                    descriptors[lease] = FdLease(owner, id, opened)
                    reply.success(mapOf("fdLeaseId" to lease, "fd" to opened.parcelFileDescriptor.fd,
                        "offset" to opened.startOffset, "declaredLength" to opened.declaredLength.takeIf { it >= 0 }, "name" to name))
                } }
                descriptor = null
            } catch (error: Exception) {
                descriptor?.close()
                main.post { synchronized(this) { opening.remove(id); job.reply?.error("uri_open_failed", error.message ?: "系统读取授权已失效。", null); job.reply = null } }
            }
        } } catch (_: RejectedExecutionException) {
            synchronized(this) { opening.remove(id); job.reply = null }
            result.error("uri_busy", "系统文件读取队列已满，请稍后重试。", null)
        }
    }
}
