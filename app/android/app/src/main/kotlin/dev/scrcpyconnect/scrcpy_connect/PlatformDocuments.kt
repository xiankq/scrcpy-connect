package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicBoolean

/** 仅拥有系统授权、选择器和原始 PFD；计划、预算及复制归应用与通用文件能力。 */
class PlatformDocuments private constructor(private val context: Context) {
    companion object {
        private var shared: PlatformDocuments? = null
        @Synchronized fun attach(activity: Activity): PlatformDocuments {
            val runtime = shared ?: PlatformDocuments(activity.applicationContext).also {shared = it}
            runtime.attachActivity(activity)
            return runtime
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val closer = Executors.newSingleThreadExecutor()
    private val operations get() = owner.operations
    private val pickers = mutableMapOf<Int, Operation>()
    private val retiredPickers = mutableSetOf<Int>()
    private var requestCode = 23100
    private val owner = DocumentPlatformOwner<Operation>()
    private val destroyed get() = owner.activity() == null
    private val resolver get() = context.contentResolver

    private fun attachActivity(activity: Activity) {
        if (owner.attach(activity)) operations.values.toList().forEach(::revoke)
    }

    private class Operation(val id: String, val ownerLeaseId: String) {
        val cancelled = AtomicBoolean()
        val signal = CancellationSignal()
        val documents = mutableMapOf<String, Uri>()
        val descriptors = mutableMapOf<String, Descriptor>()
        val pending = mutableSetOf<CompletableFuture<Unit>>()
        val closingReplies = mutableListOf<(Exception?) -> Unit>()
        var closing = false
        var releaseRequested = false
        var picker: DocumentPickerReply? = null
        var pickerMode = ""
        var pickerActivity: WeakReference<Activity>? = null
    }
    private class Descriptor(val value: ParcelFileDescriptor) {
        val completion = DocumentDescriptorLease(
            checkError = value::checkError,
            close = value::close,
            closeWithError = {value.closeWithError("文档操作未完成。")}
        )
    }
    private class Failure(val code: String, message: String) : Exception(message)
    private val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        DocumentsContract.Document.COLUMN_FLAGS)

    fun handle(activity: Activity, method: String, params: Map<String, Any?>, result: MethodChannel.Result): Boolean {
        if (!method.startsWith("documents.platform.")) return false
        if (owner.activity() !== activity) {result.error("cancelled", "文档页面已由新 Activity 接管。", null); return true}
        val action = method.removePrefix("documents.platform.")
        if (action == "openPreparedFile") {
            val path = params["path"] as? String
            if (path.isNullOrBlank()) {
                result.error("invalid_argument", "缺少已取回文件的路径。", null)
                return true
            }
            val uri = FileProvider.getUriForFile(
                context, "${context.packageName}.fileProvider.com.crazecoder.openfile", File(path),
            )
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, resolver.getType(uri) ?: "application/octet-stream")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(view, "使用其他应用打开"))
            result.success(emptyMap<String, Any>())
            return true
        }
        if (action == "environment") {
            // 与 path_provider 和 IncomingShares 共用逻辑根；Dart 固定实际根并映射其内路径，避免 /data/user/0 与 /data/data 的别名破坏词法授权。
            result.success(mapOf("cacheDirectory" to context.cacheDir.absolutePath,
                "screenshotsDirectory" to File(context.filesDir, "screenshots").absolutePath,
                "ownerLeaseId" to owner.current(), "ownerReady" to owner.accepts(owner.current())))
            return true
        }
        if (action == "claim") {claim(params, result); return true}
        val lease = params["ownerLeaseId"] as? String
        val id = params["operationId"] as? String
        if (id.isNullOrBlank() || id.length > 128) {result.error("invalid_argument", "缺少文件操作标识。", null); return true}
        val op = operations[id]
        val cleanup = action in listOf("cancel", "release", "releaseFd")
        // 当前 Activity 可收尾原代次的精确 op；错代同 id 不能触及新 op，也不能开启旧代次的新工作。
        if (cleanup) {
            if (!owner.permitsCleanup(activity, lease, op?.ownerLeaseId)) {
                result.error("cancelled", "文档清理不属于当前页面或精确操作。", null); return true
            }
        } else if (!owner.accepts(lease)) {
            result.error("cancelled", "文档平台代次已撤销或正在恢复。", null); return true
        }
        if (action == "picker") {pick(id, lease!!, params, result); return true}
        if (action == "cancel" || action == "release") {
            if (op == null) {
                result.success(mapOf("cancelled" to true, "released" to true))
            } else closeOperation(op, action == "release") {error ->
                if (error == null) result.success(mapOf("cancelled" to true, "released" to true))
                else result.error("document_cleanup_unconfirmed", error.message ?: "文档资源关闭未确认。", null)
            }
            return true
        }
        // 只释放当前代次的精确租约；失败仍由 operation 保留，不能先删映射再关闭。
        if (action == "releaseFd") {
            val outcome = params["outcome"]
            if (outcome != "success" && outcome != "abort") {
                result.error("invalid_argument", "缺少文档流完成状态。", null)
                return true
            }
            val descriptorId = params["fdLeaseId"] as? String
            val descriptor = if (op == null) null else synchronized(op) {op.descriptors[descriptorId]}
            if (descriptor == null) {result.success(mapOf("released" to false)); return true}
            closer.execute {
                try {
                    releaseDescriptor(op!!, descriptorId!!, descriptor,
                        outcome == "success" && !destroyed && !op.cancelled.get())
                    main.post {result.success(mapOf("released" to true))}
                } catch (error: Exception) {
                    main.post {result.error("close_failed", error.message ?: "系统文档流关闭未确认。", null)}
                }
            }
            return true
        }
        if (destroyed || op == null || op.cancelled.get()) {result.error("cancelled", "文档授权已释放或操作已取消。", null); return true}
        execute(op) {
            try {
                check(op)
                val uri = synchronized(op) {op.documents[params["handle"] as? String]}
                    ?: throw Failure("invalid_handle", "文档不属于本次系统授权。")
                val response: Any = when (action) {
                    "metadata" -> metadata(op, uri)
                    "children" -> children(op, uri, (params["offset"] as? Number)?.toInt() ?: 0,
                        (params["limit"] as? Number)?.toInt() ?: 256)
                    "create" -> {
                        val name = params["name"] as? String ?: throw Failure("invalid_argument", "缺少文档名称。")
                        val mime = params["mime"] as? String ?: "application/octet-stream"
                        val created = DocumentsContract.createDocument(resolver, uri, mime, name)
                            ?: throw Failure("create_failed", "提供方没有创建文档。")
                        metadata(op, created)
                    }
                    "delete" -> mapOf("deleted" to DocumentsContract.deleteDocument(resolver, uri))
                    "openFd" -> {
                        val mode = params["mode"] as? String ?: "r"
                        if (mode !in listOf("r", "rw")) throw Failure("invalid_argument", "不允许截断已有文档。")
                        val pfd = resolver.openFileDescriptor(uri, mode, op.signal)
                            ?: throw Failure("open_failed", "系统没有提供文档描述符。")
                        val lease = UUID.randomUUID().toString()
                        // 先登记精确所有权。取消后的迟到 PFD 也须由关闭栅栏等待并确认回收。
                        synchronized(op) {op.descriptors[lease] = Descriptor(pfd)}
                        check(op)
                        mapOf("fd" to pfd.fd, "fdLeaseId" to lease, "statSize" to pfd.statSize)
                    }
                    else -> throw Failure("unknown_command", "未知的文档系统适配命令。")
                }
                check(op)
                main.post {if (!op.cancelled.get()) result.success(response) else result.error("cancelled", "操作已取消。", null)}
            } catch (error: Exception) {
                main.post {result.error(if (error is Failure) error.code else if (op.cancelled.get()) "cancelled" else "documents_error", error.message, null)}
            }
        }
        return true
    }

    private fun pick(id: String, ownerLeaseId: String, params: Map<String, Any?>, result: MethodChannel.Result) {
        if (destroyed || operations.containsKey(id)) {result.error("operation_id_reused", "文档操作已结束或标识重复。", null); return}
        if (pickers.isNotEmpty() || requestCode >= 65000) {result.error("documents_busy", "已有系统文件选择器正在等待。", null); return}
        val mode = params["mode"] as? String
        val intent = when (mode) {
            "importDirectory", "exportDirectory" -> Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            "importFiles" -> Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType(params["mime"] as? String ?: "*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            "exportFile" -> Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType(params["mime"] as? String ?: "application/octet-stream").putExtra(Intent.EXTRA_TITLE, params["name"] as? String)
            else -> {result.error("invalid_argument", "未知系统文件选择方式。", null); return}
        }
        val writable = mode == "exportDirectory" || mode == "exportFile"
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or if (writable) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
        val activity = owner.activity() as? Activity
            ?: run {result.error("cancelled", "文档页面已分离。", null); return}
        val op = Operation(id, ownerLeaseId).also {
            it.picker = DocumentPickerReply(result)
            it.pickerMode = mode
            it.pickerActivity = WeakReference(activity)
        }
        operations[id] = op
        val code = requestCode++
        pickers[code] = op
        try {@Suppress("DEPRECATION") activity.startActivityForResult(intent, code)}
        catch (error: Exception) {pickers.remove(code); operations.remove(id); op.picker = null; result.error("picker_unavailable", error.message, null)}
    }
    fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (owner.activity() !== activity) return false
        val op = pickers.remove(requestCode) ?: return retiredPickers.remove(requestCode)
        val result = op.picker ?: return true
        if (destroyed || op.cancelled.get() || resultCode != Activity.RESULT_OK) {op.picker = null; result.success(mapOf("status" to "cancelled")); return true}
        val clip = if (op.pickerMode == "importFiles") data?.clipData else null
        val selected = if (clip != null) (0 until clip.itemCount).map {clip.getItemAt(it).uri} else listOfNotNull(data?.data)
        execute(op) {
            try {
                check(op)
                val documents = selected.map {chosen ->
                    if (chosen.scheme != "content") throw Failure("invalid_uri", "系统没有返回文档内容 URI。")
                    val write = op.pickerMode.startsWith("export")
                    val flags = if (write) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else Intent.FLAG_GRANT_READ_URI_PERMISSION
                    if (context.checkUriPermission(chosen, android.os.Process.myPid(), android.os.Process.myUid(), flags) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        throw Failure("permission_denied", "系统没有授予本次文档访问权限。")
                    }
                    val uri = if (DocumentsContract.isTreeUri(chosen)) DocumentsContract.buildDocumentUriUsingTree(chosen, DocumentsContract.getTreeDocumentId(chosen)) else chosen
                    mapOf("handle" to register(op, uri), "uri" to uri.toString())
                }
                check(op)
                main.post {
                    if (op.picker === result) op.picker = null
                    if (!op.cancelled.get()) result.success(mapOf("status" to "selected", "documents" to documents)) else result.success(mapOf("status" to "cancelled"))
                }
            } catch (error: Exception) {main.post {
                if (op.picker === result) op.picker = null
                result.error(if (error is Failure) error.code else "documents_error", error.message, null)
            }}
        }
        return true
    }
    private fun check(op: Operation) {
        if (destroyed || op.cancelled.get() || !owner.accepts(op.ownerLeaseId)) throw Failure("cancelled", "操作已取消。")
    }

    private fun execute(op: Operation, action: () -> Unit) {
        val finished = CompletableFuture<Unit>()
        synchronized(op) {op.pending.add(finished)}
        try {
            worker.execute {
                try {action()} finally {
                    synchronized(op) {op.pending.remove(finished)}
                    finished.complete(Unit)
                }
            }
        } catch (error: Exception) {
            synchronized(op) {op.pending.remove(finished)}
            finished.complete(Unit)
            throw error
        }
    }
    private fun register(op: Operation, uri: Uri): String = synchronized(op) {
        check(op)
        op.documents.entries.firstOrNull {it.value == uri}?.key ?: run {
            if (op.documents.size >= 20000) throw Failure("handles_busy", "本次系统文档句柄已满，请分批处理。")
            UUID.randomUUID().toString().also {op.documents[it] = uri}
        }
    }
    private fun metadata(op: Operation, uri: Uri): Map<String, Any?> {
        check(op)
        resolver.query(uri, columns, null, null, null, op.signal)?.use {cursor ->
            if (cursor.moveToFirst()) return row(op, cursor, uri)
        }
        throw Failure("document_missing", "所选文档已消失或无法读取。")
    }
    private fun row(op: Operation, cursor: android.database.Cursor, uri: Uri): Map<String, Any?> {
        fun string(column: String): String = cursor.getString(cursor.getColumnIndexOrThrow(column)) ?: ""
        fun number(column: String): Long? {val index = cursor.getColumnIndex(column); return if (index < 0 || cursor.isNull(index)) null else cursor.getLong(index)}
        val mime = string(DocumentsContract.Document.COLUMN_MIME_TYPE)
        val flags = number(DocumentsContract.Document.COLUMN_FLAGS)?.toInt() ?: 0
        return mapOf("handle" to register(op, uri), "uri" to uri.toString(), "authority" to uri.authority,
            "id" to string(DocumentsContract.Document.COLUMN_DOCUMENT_ID), "name" to string(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            "mime" to mime, "size" to number(DocumentsContract.Document.COLUMN_SIZE),
            "modified" to number(DocumentsContract.Document.COLUMN_LAST_MODIFIED)?.takeIf {it > 0}, "flags" to flags,
            "directory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
            "virtual" to (flags and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT != 0),
            "canCreate" to (flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE != 0),
            "canWrite" to (flags and DocumentsContract.Document.FLAG_SUPPORTS_WRITE != 0))
    }
    private fun children(op: Operation, parent: Uri, offset: Int, limit: Int): Map<String, Any?> {
        if (offset < 0 || limit !in 1..1000) throw Failure("invalid_argument", "分页范围无效。")
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, DocumentsContract.getDocumentId(parent))
        resolver.query(uri, columns, null, null, null, op.signal)?.use {cursor ->
            val documents = mutableListOf<Map<String, Any?>>()
            if (cursor.moveToPosition(offset)) do {
                check(op)
                val id = cursor.getString(cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
                documents.add(row(op, cursor, DocumentsContract.buildDocumentUriUsingTree(parent, id)))
            } while (documents.size < limit && cursor.moveToNext())
            return mapOf("documents" to documents, "hasMore" to (offset + documents.size < cursor.count),
                "loading" to cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false))
        }
        throw Failure("directory_read_failed", "文档提供方没有返回目录内容。")
    }
    private fun releaseDescriptor(op: Operation, id: String, descriptor: Descriptor, success: Boolean) {
        try {descriptor.completion.finish(success)} finally {
            if (descriptor.completion.released) synchronized(op) {
                if (op.descriptors[id] === descriptor) op.descriptors.remove(id)
            }
        }
    }

    private fun revoke(op: Operation) {
        op.cancelled.set(true)
        pickers.entries.filter {it.value === op}.toList().forEach {(code, _) ->
            pickers.remove(code); retiredPickers.add(code)
            try {@Suppress("DEPRECATION") op.pickerActivity?.get()?.finishActivity(code)} catch (_: Exception) {}
        }
        op.picker?.success(mapOf("status" to "cancelled")); op.picker = null
    }

    private fun closeOperation(op: Operation, release: Boolean, reply: (Exception?) -> Unit) {
        revoke(op)
        op.releaseRequested = op.releaseRequested || release
        op.closingReplies.add(reply)
        if (op.closing) return
        op.closing = true
        // 撤准入后才能取得完整等待集合；迟到 openFd 在 worker 结束前登记到同一 op。
        val pending = synchronized(op) {op.pending.toList()}
        closer.execute {
            var failure: Exception? = null
            fun attempt(action: () -> Unit) {
                try {action()} catch (error: Exception) {
                    val first = failure
                    if (first == null) failure = error else if (first !== error) first.addSuppressed(error)
                }
            }
            attempt {op.signal.cancel()}
            pending.forEach {attempt {it.join()}}
            val descriptors = synchronized(op) {op.descriptors.toMap()}
            descriptors.forEach {(id, descriptor) -> attempt {releaseDescriptor(op, id, descriptor, false)}}
            main.post {
                op.closing = false
                if (failure == null) {
                    synchronized(op) {op.documents.clear()}
                    if (op.releaseRequested && operations[op.id] === op) operations.remove(op.id)
                }
                val replies = op.closingReplies.toList()
                op.closingReplies.clear()
                replies.forEach {it(failure)}
            }
        }
    }

    private fun claim(params: Map<String, Any?>, result: MethodChannel.Result) {
        val candidate = params["ownerLeaseId"] as? String
        val expected = params["expectedOwnerLeaseId"] as? String
        if (destroyed || candidate.isNullOrBlank() || candidate.length > 128) {
            result.error("invalid_argument", "缺少文档平台代次。", null)
            return
        }
        val drain = try {owner.claim(expected, candidate)} catch (error: IllegalStateException) {
            result.error("cancelled", "文档平台已由更新代次接管。", null)
            return
        }
        if (!drain) {result.success(mapOf("claimed" to true, "ownerLeaseId" to candidate)); return}
        val retired = operations.values.toList()
        if (retired.isEmpty()) {
            if (!destroyed && owner.complete(candidate)) result.success(mapOf("claimed" to true, "ownerLeaseId" to candidate))
            else result.error("cancelled", "文档平台代次已替换。", null)
            return
        }
        var remaining = retired.size
        var failure: Exception? = null
        retired.forEach {op -> closeOperation(op, true) {error ->
            if (failure == null) failure = error
            remaining--
            if (remaining == 0) {
                if (failure != null) result.error("document_cleanup_unconfirmed", failure!!.message, null)
                else if (!destroyed && owner.complete(candidate)) result.success(mapOf("claimed" to true, "ownerLeaseId" to candidate))
                else result.error("cancelled", "文档平台代次已替换。", null)
            }
        }}
    }

    fun onDestroy(activity: Activity) {
        if (!owner.detach(activity)) return
        // Activity 分离不能证明 Rust 已排空。进程登记保留原始 PFD，待下一次 scope 接管后 claim 关闭。
        operations.values.toList().forEach(::revoke)
    }

}

/** 仅表示平台描述符关闭；关闭成功不是远端提交回执。 */
internal class DocumentDescriptorCompletion(
    private val checkError: () -> Unit,
    private val close: () -> Unit,
    private val closeWithError: () -> Unit
) {
    fun finish(success: Boolean) {
        if (!success) {
            closeWithError()
            return
        }
        var firstFailure: Exception? = null
        fun attempt(action: () -> Unit) {
            try {action()} catch (error: Exception) {
                val first = firstFailure
                if (first == null) firstFailure = error
                else if (first !== error) first.addSuppressed(error)
            }
        }
        attempt(checkError)
        attempt(close)
        // PFD 关闭通信描述符时可能缓存对端错误；关闭后不能用 canDetectErrors() 作为检查前提。
        attempt(checkError)
        firstFailure?.let {throw it}
    }
}

/** 平台仅回复一次，包括工作线程仍在等待 Binder 时取消；迟到的提供方完成只能清理，不能二次回复。 */
internal class DocumentPickerReply(result: MethodChannel.Result) {
    private var pending: MethodChannel.Result? = result
    @Synchronized private fun take(): MethodChannel.Result? = pending.also {pending = null}
    fun success(value: Any?) {take()?.success(value)}
    fun error(code: String, message: String?, details: Any?) {take()?.error(code, message, details)}
}


/** 当前技术代次在接管开始时就可发现；清理确认之前不开放任何操作准入。 */
internal class DocumentPlatformOwner<T> {
    val operations = mutableMapOf<String, T>()
    private var lease: String? = null
    private var ready = false
    private var attached: WeakReference<Any>? = null
    private var claimingActivity: WeakReference<Any>? = null
    @Synchronized fun activity(): Any? = attached?.get()
    @Synchronized fun attach(activity: Any): Boolean {
        if (attached?.get() === activity) return false
        attached = WeakReference(activity)
        claimingActivity = null
        ready = false
        return true
    }
    @Synchronized fun detach(activity: Any): Boolean {
        if (attached?.get() !== activity) return false
        attached = null
        claimingActivity = null
        ready = false
        return true
    }
    @Synchronized fun permitsCleanup(activity: Any, candidate: String?, operationLease: String?): Boolean =
        attached?.get() === activity && !candidate.isNullOrBlank() &&
            (operationLease == null || operationLease == candidate)
    @Synchronized fun current(): String? = lease
    @Synchronized fun accepts(candidate: String?): Boolean =
        attached?.get() != null && ready && lease != null && lease == candidate
    @Synchronized fun claim(expected: String?, candidate: String): Boolean {
        val activity = attached?.get() ?: error("文档页面已分离。")
        if (lease == candidate && ready) return false
        if (lease != candidate) check(lease == expected) {"文档平台代次已替换。"}
        lease = candidate
        claimingActivity = WeakReference(activity)
        ready = false
        return true
    }
    @Synchronized fun complete(candidate: String): Boolean {
        val activity = attached?.get() ?: return false
        if (lease != candidate || claimingActivity?.get() !== activity) return false
        ready = true
        return true
    }
}

/** 只有真正关闭完成后才交还所有权；对端报错仍保留其独立的结果未知语义。 */
internal class DocumentDescriptorLease(
    private val checkError: () -> Unit,
    private val close: () -> Unit,
    private val closeWithError: () -> Unit
) {
    @Volatile var released = false
        private set
    @Synchronized fun finish(success: Boolean) {
        if (released) return
        DocumentDescriptorCompletion(
            checkError = checkError,
            close = {close(); released = true},
            closeWithError = {closeWithError(); released = true}
        ).finish(success)
    }
}
