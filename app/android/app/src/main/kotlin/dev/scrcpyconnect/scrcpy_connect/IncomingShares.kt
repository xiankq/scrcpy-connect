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
import java.lang.ref.WeakReference
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/** 仅适配本次 URI 授权、原始描述符及平台技术租约；导入业务与持久发布归 Dart。 */
object IncomingShares {
    private data class Pending(val id: String, val text: String?, val mime: String?, val uris: List<Uri>) {
        fun view() = mapOf("shareId" to id, "text" to text, "mime" to mime, "sourceCount" to uris.size)
    }
    private data class Source(val descriptor: AssetFileDescriptor, val name: String)
    private val owner = IncomingShareOwner<Source>({it.descriptor.close()})
    private val signals = linkedMapOf<String, CancellationSignal>()
    private val main = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8)) { Thread(it, "interop-uri-open") }
    private val closer = Executors.newSingleThreadExecutor { Thread(it, "interop-uri-close") }
    private val pending = linkedMapOf<String, Pending>()
    private var rejection: Map<String, Any?>? = null
    private var observer: Any? = null
    private var deliver: ((Map<String, Any?>) -> Unit)? = null
    @Synchronized fun bind(owner: Any, callback: (Map<String, Any?>) -> Unit) { observer = owner; deliver = callback }
    @Synchronized fun unbind(owner: Any) { if (observer === owner) { observer = null; deliver = null } }
    fun attach(activity: Any) { owner.attach(activity).forEach {it.cancel()} }
    fun detach(activity: Any) { owner.detach(activity).forEach {it.cancel()} }
    private fun publish(payload: Map<String, Any?>) { main.post { synchronized(this) { deliver }?.invoke(payload) } }
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
    fun handle(context: Context, activity: Any, call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("sharing.platform.")) return false
        if (!owner.current(activity)) {result.error("cancelled", "分享页面已由新 Activity 接管。", null); return true}
        try {
            val lease = call.argument<String>("ownerLeaseId")
            when (call.method) {
                "sharing.platform.environment" -> result.success(mapOf(
                    "cacheDirectory" to context.cacheDir.absolutePath,
                    "ownerLeaseId" to owner.lease(), "ownerReady" to owner.accepts(owner.lease())))
                "sharing.platform.pending" -> result.success(synchronized(this) {
                    mapOf("shares" to pending.values.map {it.view()} + listOfNotNull(rejection))
                })
                "sharing.platform.claim" -> {
                    val candidate = lease ?: error("缺少分享平台代次。")
                    val retired = owner.claim(activity, call.argument("expectedOwnerLeaseId"), candidate)
                    if (retired == null) result.success(mapOf("claimed" to true, "ownerLeaseId" to candidate))
                    else {
                        val claimedBy = WeakReference(activity)
                        cleanup(retired) {error ->
                            val attached = claimedBy.get()
                            if (error != null) result.error("share_cleanup_unconfirmed", error.message, null)
                            else if (attached != null && owner.complete(attached, candidate)) result.success(mapOf("claimed" to true, "ownerLeaseId" to candidate))
                            else result.error("cancelled", "分享平台代次已替换。", null)
                        }
                    }
                }
                "sharing.platform.consume" -> {
                    check(owner.accepts(lease)) {"分享平台代次已撤销。"}
                    val id = call.argument<String>("shareId")
                    synchronized(this) {pending.remove(id); if (rejection?.get("shareId") == id) rejection = null}
                    result.success(mapOf("consumed" to true))
                }
                "sharing.platform.release" -> {
                    val id = call.argument<String>("fdLeaseId") ?: error("缺少分享描述符标识。")
                    cleanup(owner.byDescriptor(activity, lease, id)) {error ->
                        if (error == null) result.success(mapOf("released" to true))
                        else result.error("share_cleanup_unconfirmed", error.message, null)
                    }
                }
                "sharing.platform.cancel" -> {
                    val id = call.argument<String>("openId") ?: error("缺少分享打开标识。")
                    cleanup(owner.byOpen(activity, lease, id)) {error ->
                        if (error == null) result.success(mapOf("cancelled" to true))
                        else result.error("share_cleanup_unconfirmed", error.message, null)
                    }
                }
                "sharing.platform.open" -> {
                    check(owner.accepts(lease)) {"分享平台尚未完成恢复。"}
                    open(context.applicationContext, activity, lease!!, call, result)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("cancelled", error.message ?: "分享平台操作已撤销。", null)
        }
        return true
    }

    /** 调用方必须先确认 SDK 复制排空；这里再等待 Binder 打开及原始 AFD 真实关闭。 */
    private fun cleanup(resources: List<IncomingShareOpen<Source>>, reply: (Exception?) -> Unit) {
        resources.forEach {it.cancel()}
        closer.execute {
            var failure: Exception? = null
            fun attempt(action: () -> Unit) {
                try {action()} catch (error: Exception) {
                    if (failure == null) failure = error else if (failure !== error) failure.addSuppressed(error)
                }
            }
            resources.forEach {resource ->
                attempt {synchronized(this) {signals[resource.descriptorId]}?.cancel()}
                attempt {resource.drain()}
            }
            main.post {
                resources.filter {it.finished.isDone && it.released}.forEach {resource ->
                    owner.forget(resource)
                    synchronized(this) {signals.remove(resource.descriptorId)}
                }
                reply(failure)
            }
        }
    }

    private fun open(context: Context, activity: Any, lease: String, call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("openId") ?: error("缺少分享打开标识。")
        val item = synchronized(this) {pending[call.argument<String>("shareId")]} ?: error("分享授权已失效，请重新分享。")
        val index = call.argument<Number>("index")?.toInt() ?: error("缺少分享文件序号。")
        val uri = item.uris.getOrNull(index) ?: error("分享文件不存在。")
        val reply = AtomicReference<MethodChannel.Result?>(result)
        val descriptorId = UUID.randomUUID().toString()
        val job = owner.register(activity, lease, id, descriptorId) {
            reply.getAndSet(null)?.error("cancelled", "已取消打开分享来源。", null)
        }
        val signal = CancellationSignal()
        synchronized(this) {signals[descriptorId] = signal}
        try {worker.execute {
            var failure: Exception? = null
            try {
                var name = "共享文件-${index + 1}"
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, signal)?.use {cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
                }
                check(!job.cancelled.get()) {"分享打开已取消。"}
                val descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r", signal)
                    ?: error("系统未能打开此文件。")
                // 即使取消或 Activity 换代，也先登记迟到 AFD，再让关闭栅栏确认回收。
                job.opened(Source(descriptor, name))
            } catch (error: Exception) {failure = error}
            finally {job.finished.complete(Unit)}
            main.post {
                if (job.cancelled.get() || !owner.accepts(lease)) {
                    job.cancel()
                } else if (failure != null) {
                    reply.getAndSet(null)?.error("uri_open_failed", failure.message ?: "系统读取授权已失效。", null)
                } else {
                    val source = job.value()!!
                    try {
                        val response = mapOf("fdLeaseId" to descriptorId,
                            "fd" to source.descriptor.parcelFileDescriptor.fd, "offset" to source.descriptor.startOffset,
                            "declaredLength" to source.descriptor.declaredLength.takeIf {it >= 0}, "name" to source.name)
                        reply.getAndSet(null)?.success(response)
                    } catch (error: Exception) {
                        reply.getAndSet(null)?.error("uri_open_failed", error.message, null)
                    }
                }
                if (job.released) {
                    owner.forget(job)
                    synchronized(this) {signals.remove(descriptorId)}
                }
            }
        }} catch (_: RejectedExecutionException) {
            job.finished.complete(Unit)
            owner.forget(job)
            synchronized(this) {signals.remove(descriptorId)}
            reply.getAndSet(null)?.error("uri_busy", "系统文件读取队列已满，请稍后重试。", null)
        }
    }
}
