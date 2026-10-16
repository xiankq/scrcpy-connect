package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** User-selected SAF streams. No raw shared-storage path or persistent URI grant is used. */
class PlatformDocuments(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val closer = Executors.newSingleThreadExecutor()
    private val requests = mutableMapOf<Int, Operation>()
    private val issued = HashSet<String>()
    private var requestCode = 23100
    private var active: Operation? = null
    private var destroyed = false
    private var dialog: AlertDialog? = null
    private val resolver get() = activity.contentResolver

    private class Failure(val code: String, message: String) : IOException(message)
    private class Operation(val id: String, val method: String, val params: Map<String, Any?>, val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean()
        val finished = AtomicBoolean()
        val signal = CancellationSignal()
        val streams = ConcurrentHashMap.newKeySet<Closeable>()
        val visited = HashSet<String>()
        val errors = CopyOnWriteArrayList<Map<String, Any?>>()
        val renamed = CopyOnWriteArrayList<Map<String, Any?>>()
        val created = CopyOnWriteArrayList<Map<String,Any?>>()
        val imported = CopyOnWriteArrayList<Map<String,Any?>>()
        var selected = emptyList<Uri>()
        val timedOut=AtomicBoolean()
        var deadline:Runnable?=null
        var createdCount = 0
        var entries = 0
        var examined = 0
        var pathBytes = 0L
        var files = 0
        var directories = 0
        var bytes = 0L
        var skipped = 0
        var errorCount = 0
        @Volatile var writing = false
        @Volatile var started = false
        @Volatile var uri: Uri? = null
        @Volatile var local: File? = null
        var name = ""
        var conflict = params["conflict"] as? String ?: "ask"
        var sourceRoot: String? = null
        var exportTree = false
        fun check() {
            if (timedOut.get()) throw Failure("timeout","系统文档复制超过十分钟；已完成内容保留，请分批处理。")
            if (cancelled.get() || Thread.currentThread().isInterrupted) throw Failure("cancelled", "操作已取消。")
        }
        fun entry(depth: Int, path: String) {
            check(); entries++; pathBytes += path.toByteArray(Charsets.UTF_8).size
            if (entries > 10000 || depth > 64 || pathBytes > 16L * 1024 * 1024) throw Failure("tree_limit", "目录超过 10000 项、64 层或 16 MiB 路径上限，请分批选择。")
        }
        fun examine() {check();if(++examined>10000) throw Failure("tree_limit","目录超过 10000 项，请分批处理。")}
        fun error(path: String, code: String, message: String) {
            errorCount++
            if (errors.size < 1000) errors.add(mapOf("path" to path, "code" to code, "message" to message))
        }
    }
    private data class Document(val uri: Uri, val id: String, val name: String, val mime: String, val size: Long?, val modified: Long?, val flags: Int) {
        val directory get() = mime == DocumentsContract.Document.MIME_TYPE_DIR
        val virtual get() = flags and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT != 0
    }

    /** Called on the platform channel thread. Returns false for unrelated methods. */
    fun handle(method: String, params: Map<String, Any?>, result: MethodChannel.Result): Boolean {
        if (!method.startsWith("documents.")) return false
        if (method == "documents.cancel") {
            val op = active
            val matches = op != null && params["operationId"] == op.id
            if (matches) cancel(op)
            result.success(mapOf("cancelled" to matches, "operationId" to params["operationId"]))
            return true
        }
        if (method !in listOf("documents.importDirectory", "documents.importFiles", "documents.export")) { result.notImplemented(); return true }
        if (destroyed) { result.error("cancelled", "页面已关闭。", null); return true }
        if (active != null) { result.error("documents_busy", "已有文件选择或复制正在进行，请先完成或取消。", null); return true }
        val id = (params["operationId"] as? String)?.takeIf { it.isNotBlank() && it.length <= 128 } ?: UUID.randomUUID().toString()
        if (issued.size >= 10000 || !issued.add(id)) { result.error("operation_id_reused", "请使用新的文件操作标识；旧取消请求不能作用于新操作。", null); return true }
        val op = Operation(id, method, params, result)
        if (op.conflict !in listOf("ask", "skip", "keepBoth")) { result.error("invalid_argument", "系统目录仅支持询问、跳过或保留两者，不会覆盖已有文件。", null); return true }
        try {
            val intent = if (method == "documents.importDirectory") {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else if (method=="documents.importFiles") {
                Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(params["mime"] as? String ?: "*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                val source = privateSource(params["localPath"] as? String ?: throw Failure("invalid_path", "缺少本机暂存文件。"))
                op.local = source
                op.sourceRoot = source.path
                op.name = DocumentPaths.name(params["name"] as? String ?: source.name)
                val directory = OsConstants.S_ISDIR(Os.lstat(source.path).st_mode)
                op.exportTree=directory
                val kind = params["kind"] as? String ?: if (directory) "directory" else "file"
                if (kind !in listOf("file", "directory") || (kind == "directory") != directory) throw Failure("source_changed", "源类型与所选保存方式不一致。")
                if (directory && Build.VERSION.SDK_INT < 26) throw Failure("implementation_pending", "此版本的目录安全遍历尚未完成，请逐个保存文件。")
                if (directory) Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                else Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(params["mime"] as? String ?: "application/octet-stream")
                    .putExtra(Intent.EXTRA_TITLE, op.name)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            if (requestCode >= 65000) throw Failure("documents_busy", "本次页面已达到文件选择次数上限，请重新打开页面。")
            val code = requestCode++
            active = op; requests[code] = op
            @Suppress("DEPRECATION") activity.startActivityForResult(intent, code)
        } catch (error: Exception) {
            active = null
            requests.entries.removeAll {it.value===op}
            result.error(if (error is Failure) error.code else "documents_error", error.message, null)
        }
        return true
    }

    /** Every request has a distinct code; a cancelled picker's late result cannot start a new operation. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val op = requests.remove(requestCode) ?: return false
        if (destroyed || op.cancelled.get() || active !== op) return true
        val selected=if(op.method=="documents.importFiles" && data?.clipData!=null) {
            val clip=data.clipData!!
            if(clip.itemCount>1000) {op.error("","selection_limit","最多选择 1000 个文件，请分批导入。");finish(op,"partial");return true}
            (0 until clip.itemCount).map {clip.getItemAt(it).uri}
        } else listOfNotNull(data?.data)
        val uri=selected.firstOrNull()
        if (resultCode != Activity.RESULT_OK || uri == null) { finish(op, "cancelled"); return true }
        op.selected=selected
        if(selected.any {it.scheme!="content"}) {op.error("","invalid_uri","系统没有返回文档内容 URI。");finish(op,"partial");return true}
        if (uri.scheme != "content") { op.error("", "invalid_uri", "系统没有返回文档内容 URI。"); finish(op, "partial"); return true }
        op.uri = uri; op.started = true
        op.deadline=Runnable {if(!op.finished.get()) {op.timedOut.set(true);cancel(op)}}.also {main.postDelayed(it,10L*60*1000)}
        if (op.method=="documents.export" && !op.exportTree) op.writing=true
        worker.execute {
            try {
                if (op.method == "documents.importDirectory") importDirectory(op, uri)
                else if(op.method=="documents.importFiles") importFiles(op)
                else if (op.exportTree) exportDirectory(op, uri)
                else exportFile(op, uri)
                op.check()
                finish(op, if (op.errorCount > 0 || op.skipped > 0) "partial" else if (op.method.startsWith("documents.import")) "imported" else "saved")
            } catch (error: Exception) {
                val code = if (error is Failure) error.code else if(op.timedOut.get()) "timeout" else if (op.cancelled.get()) "cancelled" else "documents_error"
                op.error(op.name, code, error.message ?: "系统文件操作未完成。")
                finish(op, if (code=="result_unknown") "resultUnknown" else if (op.writing) "partial" else if (code == "cancelled") "cancelled" else "partial")
            } finally {
                op.streams.toList().forEach { try { it.close() } catch (_: Exception) {} }
            }
        }
        return true
    }

    fun onDestroy() {
        destroyed = true
        active?.let { op ->
            cancel(op)
            if (op.started) finish(op, if (op.writing) "resultUnknown" else "cancelled")
        }
        requests.values.forEach { it.cancelled.set(true) }
        requests.clear(); dialog?.dismiss(); dialog = null
        worker.shutdown(); closer.shutdown()
    }

    private fun cancel(op: Operation) {
        op.cancelled.set(true)
        requests.entries.filter {it.value===op}.forEach { (code,_) -> try { @Suppress("DEPRECATION") activity.finishActivity(code) } catch (_:Exception) {} }
        dialog?.dismiss(); dialog = null
        closer.execute {
            try { op.signal.cancel() } catch (_: Exception) {}
            op.streams.toList().forEach { try { it.close() } catch (_: Exception) {} }
        }
        if (!op.started) finish(op, "cancelled")
    }

    private fun finish(op: Operation, status: String) {
        if (!op.finished.compareAndSet(false, true)) return
        op.deadline?.let {main.removeCallbacks(it)}
        val response = mapOf("operationId" to op.id, "status" to status, "localPath" to op.local?.path,
            "uri" to op.uri?.toString(), "name" to op.name, "bytes" to op.bytes, "files" to op.files,
            "directories" to op.directories, "skipped" to op.skipped, "errors" to op.errors.toList(),
            "errorCount" to op.errorCount, "errorsTruncated" to (op.errorCount > op.errors.size),
            "renamed" to op.renamed.toList(), "created" to op.created.toList(), "createdCount" to op.createdCount,
            "items" to op.imported.toList(),
            "atomic" to false, "saveMode" to (if(op.method.startsWith("documents.import")) "cacheSnapshot" else "providerStream"),
            "partialDestinationPossible" to (op.writing && status !in listOf("saved", "imported")),
            "sourceValidation" to "sizeAndMtimeWhenAvailable", "cacheRetained" to (op.local != null))
        main.post { if (active === op) active = null; try { op.result.success(response) } catch (_: Exception) {} }
    }

    private fun privateSource(path: String): File {
        val source = File(path)
        if (!source.isAbsolute || OsConstants.S_ISLNK(Os.lstat(source.path).st_mode)) throw Failure("invalid_path", "保存源必须是应用本机暂存中的普通文件或目录，不能是符号链接。")
        val canonical = source.canonicalFile
        if (!DocumentPaths.inside(activity.cacheDir.canonicalFile, canonical) && !DocumentPaths.inside(File(activity.filesDir,"screenshots").canonicalFile, canonical)) throw Failure("invalid_path", "只能导出应用私有暂存或截图内容，请先取回文件。")
        val mode = Os.lstat(canonical.path).st_mode
        if (!OsConstants.S_ISREG(mode) && !OsConstants.S_ISDIR(mode)) throw Failure("invalid_path", "保存源必须是普通文件或目录。")
        return canonical
    }

    private fun treeRoot(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    private val columns get() = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED, DocumentsContract.Document.COLUMN_FLAGS)
    private fun document(uri: Uri, op: Operation): Document {
        op.check()
        resolver.query(uri, columns, null, null, null, op.signal)?.use { cursor ->
            if (cursor.moveToFirst()) return readDocument(cursor, uri)
        }
        throw Failure("document_missing", "所选文档已消失或无法读取。")
    }
    private fun readDocument(cursor: android.database.Cursor, uri: Uri): Document {
        fun string(column: String): String = cursor.getString(cursor.getColumnIndexOrThrow(column)) ?: ""
        fun number(column: String): Long? { val index = cursor.getColumnIndex(column); return if (index < 0 || cursor.isNull(index)) null else cursor.getLong(index) }
        return Document(uri, string(DocumentsContract.Document.COLUMN_DOCUMENT_ID), string(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            string(DocumentsContract.Document.COLUMN_MIME_TYPE), number(DocumentsContract.Document.COLUMN_SIZE),
            number(DocumentsContract.Document.COLUMN_LAST_MODIFIED)?.takeIf { it > 0 }, number(DocumentsContract.Document.COLUMN_FLAGS)?.toInt() ?: 0)
    }
    private fun children(parent: Uri, op: Operation, visit: (Document) -> Unit) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(parent, DocumentsContract.getDocumentId(parent))
        resolver.query(children, columns, null, null, null, op.signal)?.use { cursor ->
            var count=0
            while (cursor.moveToNext()) {
                op.check()
                if (++count>10000) throw Failure("tree_limit","文档目录超过 10000 项，请分批处理。")
                val id = cursor.getString(cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
                visit(readDocument(cursor, DocumentsContract.buildDocumentUriUsingTree(parent, id)))
            }
            if (cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)) throw Failure("provider_loading", "文档提供方尚未完成目录加载，请稍后重新选择。")
            return
        }
        throw Failure("directory_read_failed", "文档提供方没有返回目录内容。")
    }

    private fun importDirectory(op: Operation, selected: Uri) {
        op.examine()
        val root = document(treeRoot(selected), op)
        if (!root.directory || root.virtual) throw Failure("not_a_directory", "请选择可读取的普通文档目录。")
        op.name = DocumentPaths.name(root.name)
        val owner = File(activity.cacheDir, "documents/${UUID.randomUUID()}")
        if (!owner.mkdirs()) throw Failure("cache_error", "无法准备本机暂存目录。")
        val target = File(owner, op.name); op.local = target
        importNode(op, root, target, 0, op.name)
    }
    private fun importFiles(op:Operation) {
        val owner=File(activity.cacheDir,"documents/${UUID.randomUUID()}")
        if(!owner.mkdirs()) throw Failure("cache_error","无法准备本机暂存目录。")
        op.local=owner;op.name="所选文件"
        for((index,uri) in op.selected.withIndex()) {
            op.examine()
            try {
                val source=document(uri,op)
                if(source.directory) throw Failure("not_a_file","文件选择器返回了目录，请使用发送本机文件夹。")
                val name=DocumentPaths.name(source.name)
                val parent=File(owner,index.toString())
                if(!parent.mkdir()) throw Failure("cache_error","无法准备独立文件暂存位置。")
                val target=File(parent,name)
                importNode(op,source,target,0,name)
                if(target.isFile) op.imported.add(mapOf("localPath" to target.path,"name" to name))
            } catch(error:Exception) {recordOrThrow(op,"所选文件 ${index+1}",error)}
        }
    }
    private fun importNode(op: Operation, source: Document, target: File, depth: Int, relative: String) {
        op.entry(depth, relative)
        if (!op.visited.add("${source.uri.authority}:${source.id}")) { op.skipped++; op.error(relative, "document_cycle", "提供方重复返回同一文档，未继续递归。"); return }
        if (source.virtual) { op.skipped++; op.error(relative, "virtual_document", "虚拟文档未自动转换或下载。"); return }
        if (source.directory) {
            if (!target.mkdir()) throw Failure("cache_conflict", "暂存目录名称冲突，未覆盖原内容。")
            op.writing=true
            op.directories++
            val names = HashSet<String>()
            children(source.uri, op) { child ->
                op.examine()
                try {
                    val name = DocumentPaths.name(child.name)
                    if (!names.add(name)) throw Failure("duplicate_name", "提供方返回同名项目，未合并或覆盖。")
                    importNode(op, child, File(target, name), depth + 1, "$relative/$name")
                } catch (error: Exception) { recordOrThrow(op, "$relative/${child.name}", error) }
            }
            val after = document(source.uri, op)
            if (after.id!=source.id || !after.directory || source.modified != null && after.modified != source.modified) op.error(relative, "source_changed", "目录在复制期间发生变化；该快照未完整确认。")
        } else {
            if (source.size != null && source.size > activity.cacheDir.usableSpace - 32L * 1024 * 1024) throw Failure("cache_full", "本机暂存空间不足，未下载此文件。")
            val part = File(target.parentFile, ".interop-${UUID.randomUUID()}.part")
            if (!part.createNewFile()) throw Failure("cache_conflict", "无法创建独立暂存文件。")
            try {
                val pfd = resolver.openFileDescriptor(source.uri, "r", op.signal) ?: throw Failure("read_failed", "提供方没有打开文件流。")
                tracked(op, ParcelFileDescriptor.AutoCloseInputStream(pfd)) { input ->
                    tracked(op, FileOutputStream(part)) { output -> copy(op, input, output); output.fd.sync() }
                }
                val after = document(source.uri, op)
                if (after.id!=source.id || after.directory || (source.size != null && part.length() != source.size) || (source.size != null && after.size != source.size) || (source.modified != null && after.modified != source.modified)) throw Failure("source_changed", "源文件在复制期间发生变化；未提交暂存文件。")
                op.check()
                if (target.exists() || !part.renameTo(target)) throw Failure("cache_conflict", "本机暂存目标发生变化，未覆盖原内容。")
                op.files++
            } finally { if (part.exists()) part.delete() }
        }
    }

    private fun exportFile(op: Operation, uri: Uri) {
        op.examine()
        val source = privateSource(op.local!!.path)
        val target = document(uri, op)
        if (target.directory || target.virtual) throw Failure("invalid_target", "提供方返回了不适合写入的文档。")
        op.name = target.name
        writeFile(op, source, target, source.name)
    }
    private fun exportDirectory(op: Operation, selected: Uri) {
        op.examine()
        val source = privateSource(op.local!!.path)
        val parent = document(treeRoot(selected), op)
        if (!parent.directory || parent.flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE == 0) throw Failure("create_unavailable", "所选提供方目录没有新建能力；本机暂存已保留。")
        val root = create(op, parent, op.name, DocumentsContract.Document.MIME_TYPE_DIR) ?: return
        op.uri = root.uri; op.name = root.name
        exportNode(op, source, root, 0, op.name)
    }
    private fun exportNode(op: Operation, source: File, target: Document, depth: Int, relative: String) {
        op.entry(depth, relative)
        checkedSource(op,source)
        val before = Os.lstat(source.path)
        if (OsConstants.S_ISDIR(before.st_mode)) {
            op.directories++
            if (Build.VERSION.SDK_INT < 26) throw Failure("implementation_pending", "此版本的目录安全遍历尚未完成。")
            Files.newDirectoryStream(source.toPath()).use { entries ->
                for (path in entries) {
                    op.examine()
                    if(depth>=64) throw Failure("tree_limit","目录超过 64 层，请分批处理。")
                    val child = path.toFile()
                    try {
                        val name = DocumentPaths.name(child.name)
                        val mode = Os.lstat(child.path).st_mode
                        if (OsConstants.S_ISLNK(mode) || (!OsConstants.S_ISREG(mode) && !OsConstants.S_ISDIR(mode))) { op.skipped++; op.error("$relative/$name", "not_followed", "符号链接和特殊文件不会自动跟随。"); continue }
                        val mime = if (OsConstants.S_ISDIR(mode)) DocumentsContract.Document.MIME_TYPE_DIR else "application/octet-stream"
                        val destination = create(op, target, name, mime) ?: continue
                        exportNode(op, child, destination, depth + 1, "$relative/$name")
                    } catch (error: Exception) { recordOrThrow(op, "$relative/${child.name}", error) }
                }
            }
            val after = Os.lstat(source.path)
            if (before.st_mtime != after.st_mtime || before.st_ino != after.st_ino) op.error(relative, "source_changed", "源目录在保存期间发生变化，已保存项目保留。")
        } else writeFile(op, source, target, relative)
    }

    private fun create(op: Operation, parent: Document, requested: String, mime: String): Document? {
        op.check()
        val names = HashSet<String>(); val ids = HashSet<String>()
        children(parent.uri, op) { child ->
            if (names.size >= 10000) throw Failure("tree_limit", "目标目录项目过多，无法安全核对冲突。")
            names.add(child.name); ids.add(child.id)
        }
        var name = DocumentPaths.name(requested)
        if (name in names) {
            val decision = if (op.conflict == "ask") conflict(op, name) else op.conflict
            if (decision == "cancel") throw Failure("cancelled", "已取消保存；已完成内容保留。")
            if (decision == "skip") { op.skipped++; return null }
            name = "$name (${UUID.randomUUID()})"
        }
        op.check()
        val fresh = document(parent.uri, op)
        if (!fresh.directory || fresh.flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE == 0) throw Failure("target_changed", "目标目录的新建能力已变化。")
        op.writing = true // Creation can be visible even if the Binder reply is lost.
        val uri = try { DocumentsContract.createDocument(resolver, parent.uri, mime, name) ?: throw Failure("create_failed", "提供方没有创建新文档。") }
            catch(error:Failure) {throw error}
            catch(error:Exception) {throw Failure("result_unknown","文档创建结果尚不确定，请核对目标目录；不会自动重试。")}
        if (op.createdCount++==0) op.uri=uri
        if (op.created.size<1000) op.created.add(mapOf("uri" to uri.toString(),"name" to name))
        val created = document(uri, op)
        if(op.createdCount==1) op.name=created.name
        if(op.createdCount<=1000) op.created[op.createdCount-1]=mapOf("uri" to uri.toString(),"name" to created.name)
        if (created.id in ids || created.name != name || created.directory!=(mime==DocumentsContract.Document.MIME_TYPE_DIR)) throw Failure("target_changed", "提供方返回了已有文档、不同类型或修改了名称；未写入内容，请核对已创建的空项目。")
        var sameName = 0
        children(parent.uri, op) { child -> if (child.name == name) sameName++ }
        if (sameName != 1) throw Failure("target_changed", "目标在创建期间出现同名竞争；未写入内容，请核对空项目。")
        if (name != requested && op.renamed.size < 1000) op.renamed.add(mapOf("requested" to requested, "name" to name, "uri" to uri.toString()))
        return created
    }
    private fun writeFile(op: Operation, source: File, target: Document, relative: String) {
        op.check(); checkedSource(op,source)
        val before = Os.lstat(source.path)
        if (!OsConstants.S_ISREG(before.st_mode)) throw Failure("source_changed", "源文件类型已变化，未跟随符号链接。")
        val fresh = document(target.uri, op)
        if (fresh.id != target.id || fresh.directory || (fresh.size != null && fresh.size != 0L)) throw Failure("target_changed", "目标不是刚创建的空文档，未覆盖已有内容。")
        if (fresh.flags and DocumentsContract.Document.FLAG_SUPPORTS_WRITE==0) throw Failure("write_unavailable","提供方没有声明文档写入能力，本机暂存已保留。")
        // rw preserves existing content while opening; unlike w/rwt it cannot
        // truncate a file that changed before we inspect the descriptor.
        val pfd = resolver.openFileDescriptor(target.uri, "rw", op.signal) ?: throw Failure("write_unavailable", "提供方没有可安全核验的写入流。")
        tracked(op, ParcelFileDescriptor.AutoCloseOutputStream(pfd)) { output ->
            if (pfd.statSize != 0L) throw Failure("target_changed", "提供方不能确认目标为空，未写入内容。")
            op.writing = true
            val descriptor=Os.open(source.path,OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_CLOEXEC,0)
            tracked(op, FileInputStream(descriptor)) { input ->
                val opened=Os.fstat(descriptor)
                if (opened.st_ino!=before.st_ino || opened.st_dev!=before.st_dev || !OsConstants.S_ISREG(opened.st_mode)) throw Failure("source_changed","源文件在打开期间发生变化，未读取替换内容。")
                copy(op, input, output)
            }
            output.flush()
        }
        val after = Os.lstat(source.path)
        if (before.st_ino != after.st_ino || before.st_size != after.st_size || before.st_mtime != after.st_mtime) throw Failure("source_changed", "源文件在保存期间变化，目标可能包含部分或混合内容，请核对后重新保存。")
        val saved = document(target.uri, op)
        if (saved.size != null && saved.size != before.st_size) throw Failure("result_unknown", "提供方返回的保存长度不一致，请核对目标；本机暂存已保留。")
        op.files++
    }
    private fun checkedSource(op:Operation,source:File) {
        val checked=privateSource(source.path)
        val root=File(op.sourceRoot ?: throw Failure("invalid_path","缺少源快照范围。"))
        if (checked.path!=root.path && !DocumentPaths.inside(root,checked)) throw Failure("source_changed","源目录路径已被替换，未读取所选快照范围以外的内容。")
    }
    private fun copy(op: Operation, input: java.io.InputStream, output: java.io.OutputStream) {
        val buffer = ByteArray(64 * 1024)
        while (true) {
            op.check(); val count = input.read(buffer); if (count < 0) break; if (count == 0) continue
            if (op.bytes > 8L * 1024 * 1024 * 1024 - count) throw Failure("byte_limit", "本次复制超过 8 GiB 上限，请分批处理。")
            op.check(); output.write(buffer, 0, count); op.bytes += count
        }
    }
    private fun <T : Closeable, R> tracked(op: Operation, stream: T, block: (T) -> R): R {
        op.streams.add(stream)
        try { return stream.use {op.check();block(it)} } finally { op.streams.remove(stream) }
    }
    private fun recordOrThrow(op: Operation, path: String, error: Exception) {
        if (op.cancelled.get() || error is Failure && error.code in listOf("cancelled", "tree_limit", "byte_limit")) throw error
        op.skipped++; op.error(path, if (error is Failure) error.code else "documents_error", error.message ?: "此项未完成。")
    }
    private fun conflict(op: Operation, name: String): String {
        val done = CountDownLatch(1)
        var choice = "cancel"
        main.post {
            if (destroyed || op.cancelled.get() || active !== op) { done.countDown(); return@post }
            dialog = AlertDialog.Builder(activity).setTitle("存在同名项目")
                .setMessage("$name\n系统文档提供方不能保证原子覆盖。请选择保留两者、跳过或取消；本机暂存会保留。")
                .setPositiveButton("保留两者") { _, _ -> choice = "keepBoth"; done.countDown() }
                .setNeutralButton("跳过") { _, _ -> choice = "skip"; done.countDown() }
                .setNegativeButton("取消") { _, _ -> done.countDown() }
                .setOnCancelListener { done.countDown() }.create().also { it.show() }
        }
        while (!done.await(100, TimeUnit.MILLISECONDS)) op.check()
        op.check(); return choice
    }
}

/** Pure path rules are also exercised by the standalone native contract test. */
internal object DocumentPaths {
    fun name(value: String): String {
        require(value.isNotEmpty() && value != "." && value != ".." && value.length <= 255 && value.none { it == '/' || it == '\\' || it == '\u0000' || it == '\n' || it == '\r' }) { "文档名称包含不安全的路径字符。" }
        return value
    }
    fun inside(root: File, file: File): Boolean = file.path.startsWith(root.path + File.separator)
}
