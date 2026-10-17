package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** OS capabilities only. Tree planning, naming, quotas, copying and result
 * semantics live in the shared DocumentsCoordinator / document core. */
class PlatformDocuments(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val closer = Executors.newSingleThreadExecutor()
    private val operations = mutableMapOf<String, Operation>()
    private val pickers = mutableMapOf<Int, Operation>()
    private val retiredPickers = mutableSetOf<Int>()
    private var requestCode = 23100
    private var destroyed = false
    private val resolver get() = activity.contentResolver

    private class Operation(val id: String) {
        val cancelled = AtomicBoolean()
        val signal = CancellationSignal()
        val documents = mutableMapOf<String, Uri>()
        val descriptors = mutableMapOf<String, ParcelFileDescriptor>()
        var picker: DocumentPickerReply? = null
        var pickerMode = ""
    }
    private class Failure(val code: String, message: String) : Exception(message)
    private val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        DocumentsContract.Document.COLUMN_FLAGS)

    fun handle(method: String, params: Map<String, Any?>, result: MethodChannel.Result): Boolean {
        if (!method.startsWith("documents.platform.")) return false
        val action = method.removePrefix("documents.platform.")
        if (action == "environment") {
            // Match path_provider and IncomingShares. Canonicalization can
            // change Android's /data/user/0 alias to /data/data, breaking the
            // shared lexical capability root without changing the directory.
            result.success(mapOf("cacheDirectory" to activity.cacheDir.absolutePath,
                "screenshotsDirectory" to File(activity.filesDir, "screenshots").absolutePath))
            return true
        }
        val id = params["operationId"] as? String
        if (id.isNullOrBlank() || id.length > 128) {result.error("invalid_argument", "缺少文件操作标识。", null); return true}
        if (action == "picker") {pick(id, params, result); return true}
        val op = operations[id]
        if (action == "cancel" || action == "release") {
            if (op != null) {cancel(op); if (action == "release") operations.remove(id)}
            result.success(mapOf("cancelled" to (op != null)))
            return true
        }
        // Lease cleanup remains valid after cancellation. Unknown or already
        // closed leases are idempotent and cannot address another operation.
        if (action == "releaseFd") {
            val outcome = params["outcome"]
            if (outcome != "success" && outcome != "abort") {
                result.error("invalid_argument", "缺少文档流完成状态。", null)
                return true
            }
            val lease = params["fdLeaseId"] as? String
            val descriptor = if (op == null) null else synchronized(op) {op.descriptors.remove(lease)}
            if (descriptor == null) {result.success(mapOf("released" to false)); return true}
            worker.execute {
                try {
                    completeDescriptor(descriptor, outcome == "success" &&
                        !destroyed && op != null && !op.cancelled.get())
                    main.post {result.success(mapOf("released" to true))}
                } catch (error: Exception) {
                    main.post {result.error("close_failed", error.message ?: "系统文档流关闭未确认。", null)}
                }
            }
            return true
        }
        if (destroyed || op == null || op.cancelled.get()) {result.error("cancelled", "文档授权已释放或操作已取消。", null); return true}
        worker.execute {
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
                        synchronized(op) {
                            if (op.cancelled.get()) {completeDescriptor(pfd, false); throw Failure("cancelled", "操作已取消。")}
                            op.descriptors[lease] = pfd
                        }
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

    private fun pick(id: String, params: Map<String, Any?>, result: MethodChannel.Result) {
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
        val op = Operation(id).also {it.picker = DocumentPickerReply(result); it.pickerMode = mode!!}
        operations[id] = op
        val code = requestCode++
        pickers[code] = op
        try {@Suppress("DEPRECATION") activity.startActivityForResult(intent, code)}
        catch (error: Exception) {pickers.remove(code); operations.remove(id); op.picker = null; result.error("picker_unavailable", error.message, null)}
    }
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val op = pickers.remove(requestCode) ?: return retiredPickers.remove(requestCode)
        val result = op.picker ?: return true
        if (destroyed || op.cancelled.get() || resultCode != Activity.RESULT_OK) {op.picker = null; result.success(mapOf("status" to "cancelled")); return true}
        val clip = if (op.pickerMode == "importFiles") data?.clipData else null
        val selected = if (clip != null) (0 until clip.itemCount).map {clip.getItemAt(it).uri} else listOfNotNull(data?.data)
        worker.execute {
            try {
                check(op)
                val documents = selected.map {chosen ->
                    if (chosen.scheme != "content") throw Failure("invalid_uri", "系统没有返回文档内容 URI。")
                    val write = op.pickerMode.startsWith("export")
                    val flags = if (write) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else Intent.FLAG_GRANT_READ_URI_PERMISSION
                    if (activity.checkUriPermission(chosen, android.os.Process.myPid(), android.os.Process.myUid(), flags) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
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
    private fun check(op: Operation) {if (destroyed || op.cancelled.get()) throw Failure("cancelled", "操作已取消。")}
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
    private fun completeDescriptor(descriptor: ParcelFileDescriptor, success: Boolean) {
        DocumentDescriptorCompletion(
            checkError = descriptor::checkError,
            close = descriptor::close,
            closeWithError = {descriptor.closeWithError("文档操作未完成。")}
        ).finish(success)
    }
    private fun cancel(op: Operation) {
        op.cancelled.set(true)
        pickers.entries.filter {it.value === op}.toList().forEach {(code, _) ->
            pickers.remove(code); retiredPickers.add(code)
            try {@Suppress("DEPRECATION") activity.finishActivity(code)} catch (_: Exception) {}
        }
        op.picker?.success(mapOf("status" to "cancelled")); op.picker = null
        // Closing a descriptor and cancelling a provider call may block Binder;
        // use the one bounded worker rather than the platform/UI thread.
        closer.execute {
            try {op.signal.cancel()} catch (_: Exception) {}
            val fds = synchronized(op) {op.descriptors.values.toList().also {op.descriptors.clear()}}
            fds.forEach {try {completeDescriptor(it, false)} catch (_: Exception) {}}
        }
    }
    fun onDestroy() {
        destroyed = true
        operations.values.toList().forEach(::cancel)
        operations.clear(); pickers.clear(); worker.shutdown(); closer.shutdown()
    }
}

/** Platform descriptor signals only; a successful close is not a remote commit ACK. */
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
        // PFD may cache a peer error while closing its communication FD.
        // Do not gate this check on canDetectErrors() after close.
        attempt(checkError)
        firstFailure?.let {throw it}
    }
}

/** Exactly one platform reply, including cancel while a worker is still waiting
 * on Binder. A late provider completion may clean up but cannot reply twice. */
internal class DocumentPickerReply(result: MethodChannel.Result) {
    private var pending: MethodChannel.Result? = result
    @Synchronized private fun take(): MethodChannel.Result? = pending.also {pending = null}
    fun success(value: Any?) {take()?.success(value)}
    fun error(code: String, message: String?, details: Any?) {take()?.error(code, message, details)}
}
