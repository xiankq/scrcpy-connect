package dev.scrcpyconnect.scrcpy_connect

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaCodecList
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.DataInputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/** Packet timestamps and session boundaries survive ADB -> Rust -> MediaCodec.
 *  Pixels stay in the decoder Surface/Flutter Texture, never in a Dart event. */
class RemoteVideoDecoder(
    val sessionId: String,
    private val deviceId: String?,
    private val registry: TextureRegistry,
    private val emit: (Map<String, Any?>) -> Unit,
    private val codecName: String = "h264",
) {
    companion object {
        val mimeTypes = mapOf("h264" to "video/avc", "h265" to "video/hevc", "av1" to "video/av01",
            "vp8" to "video/x-vnd.on2.vp8", "vp9" to "video/x-vnd.on2.vp9")

        /** Enumeration is a preflight only; configure and a rendered frame are still required. */
        fun capabilities(): Map<String, Any?> {
            val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
            return mapOf("codecs" to mimeTypes.map { (id, mime) ->
                val matches = codecs.filter { info -> info.supportedTypes.any { it.equals(mime, true) } }
                mapOf("id" to id, "mime" to mime, "available" to matches.isNotEmpty(),
                    "status" to if (matches.isNotEmpty()) "available" else "unavailable",
                    "decoders" to matches.map { info ->
                        val caps = info.getCapabilitiesForType(mime)
                        mapOf("name" to info.name, "maxInstances" to caps.maxSupportedInstances,
                            "hardwareAccelerated" to if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated else null,
                            "softwareOnly" to if (Build.VERSION.SDK_INT >= 29) info.isSoftwareOnly else null)
                    })
            }, "probe" to "MediaCodecList", "configurationVerified" to false)
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val stopped = AtomicBoolean(false)
    private val reported = AtomicBoolean(false)
    private val reportNextFrame = AtomicBoolean(true)
    @Volatile private var paused = false
    private val codecLock = Any()
    private val texture = registry.createSurfaceTexture()
    private val surface = Surface(texture.surfaceTexture())
    private var codec: MediaCodec? = null
    private var socket: Socket? = null
    private var initialResult: MethodChannel.Result? = null
    @Volatile private var width = 0
    @Volatile private var height = 0
    @Volatile private var streamWidth = 0
    @Volatile private var streamHeight = 0
    @Volatile private var frames = 0L
    @Volatile private var packetsQueued = 0L
    @Volatile private var outputsReleased = 0L
    @Volatile private var rendererName = ""
    @Volatile private var hardware: Boolean? = null

    fun start(port: Int, token: String, result: MethodChannel.Result) {
        initialResult = result
        main.postDelayed({
            if (!reported.get()) {
                android.util.Log.w("ConnectVideo", "first frame timed out decoder=$rendererName queued=$packetsQueued released=$outputsReleased paused=$paused")
                fail("frame_timeout", "已连接设备，但未在期限内解码出首帧。")
            }
        }, 20_000)
        Thread({ readPackets(port, token) }, "interop-video-$sessionId").start()
        Thread({ drainOutput() }, "interop-render-$sessionId").start()
    }

    private fun configure(w: Int, h: Int) = synchronized(codecLock) {
        check(!stopped.get()) { "Video session already stopped" }
        require(w in 1..16384 && h in 1..16384 && w.toLong() * h <= 67_108_864) { "Invalid video dimensions" }
        if (codec != null && streamWidth == w && streamHeight == h) return@synchronized
        codec?.let { runCatching { it.stop() }; it.release() }
        width = w
        height = h
        streamWidth = w
        streamHeight = h
        texture.surfaceTexture().setDefaultBufferSize(w, h)
        val mime = mimeTypes[codecName] ?: throw IllegalArgumentException("Unknown video codec")
        val format = MediaFormat.createVideoFormat(mime, w, h)
        format.setInteger(MediaFormat.KEY_PRIORITY, 0)
        val decoder = MediaCodec.createDecoderByType(mime)
        try {
            rendererName = decoder.name
            if (Build.VERSION.SDK_INT >= 29) hardware = decoder.codecInfo.isHardwareAccelerated
            if (Build.VERSION.SDK_INT >= 30 && decoder.codecInfo.getCapabilitiesForType(mime)
                    .isFeatureSupported(android.media.MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            decoder.configure(format, surface, null, 0)
            decoder.setOnFrameRenderedListener({ _, pts, _ -> onRendered(pts) }, main)
            decoder.start()
            codec = decoder
        } catch (error: Exception) {
            runCatching { decoder.release() }
            codec = null
            throw error
        }
    }

    private fun readPackets(port: Int, token: String) {
        try {
            require(port in 1..65535 && token.length == 64) { "Invalid video endpoint" }
            val connection = Socket()
            synchronized(codecLock) {
                if (stopped.get()) { connection.close(); return }
                socket = connection
            }
            connection.tcpNoDelay = true
            connection.connect(InetSocketAddress("127.0.0.1", port), 10_000)
            connection.getOutputStream().write((token + "\n").toByteArray(Charsets.US_ASCII))
            connection.getOutputStream().flush()
            val input = DataInputStream(connection.getInputStream().buffered(65_536))
            while (!stopped.get()) {
                val first = input.readInt()
                if ((first and Int.MIN_VALUE) != 0) {
                    configure(input.readInt(), input.readInt())
                    continue
                }
                val low = input.readInt()
                val ptsFlags = (first.toLong() shl 32) or (low.toLong() and 0xffffffffL)
                val length = input.readInt()
                require(length in 1..16_777_216) { "Invalid video packet length" }
                val data = ByteArray(length)
                input.readFully(data)
                val flags = if ((ptsFlags and (1L shl 62)) != 0L) MediaCodec.BUFFER_FLAG_CODEC_CONFIG
                    else if ((ptsFlags and (1L shl 61)) != 0L) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                val pts = if (flags == MediaCodec.BUFFER_FLAG_CODEC_CONFIG) 0 else ptsFlags and ((1L shl 61) - 1)
                queue(data, pts, flags)
            }
        } catch (error: Exception) {
            if (!stopped.get()) fail(codecFailureCode(error, "video_stream_error"), error.message ?: "远端视频流已中断。")
        }
    }

    private fun queue(bytes: ByteArray, pts: Long, flags: Int) {
        while (!stopped.get()) {
            if (paused) { Thread.sleep(10); continue }
            val queued = synchronized(codecLock) {
                val decoder = codec ?: throw IllegalStateException("Video packet preceded session metadata")
                val index = decoder.dequeueInputBuffer(0)
                if (index < 0) false else {
                    val buffer = decoder.getInputBuffer(index) ?: throw IllegalStateException("Missing codec input")
                    require(buffer.capacity() >= bytes.size) { "Encoded packet exceeds decoder input capacity" }
                    buffer.clear()
                    buffer.put(bytes)
                    decoder.queueInputBuffer(index, 0, bytes.size, pts, flags)
                    packetsQueued++
                    true
                }
            }
            if (queued) return
            Thread.sleep(2)
        }
    }

    private fun drainOutput() {
        val info = MediaCodec.BufferInfo()
        while (!stopped.get()) {
            try {
                if (paused) { Thread.sleep(20); continue }
                synchronized(codecLock) {
                    codec?.let { decoder ->
                        val index = decoder.dequeueOutputBuffer(info, 0)
                        if (index >= 0) {
                            decoder.releaseOutputBuffer(index, true)
                            outputsReleased++
                        }
                        else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val output = decoder.outputFormat
                            width = if (output.containsKey("crop-right") && output.containsKey("crop-left"))
                                output.getInteger("crop-right") - output.getInteger("crop-left") + 1 else output.getInteger(MediaFormat.KEY_WIDTH)
                            height = if (output.containsKey("crop-bottom") && output.containsKey("crop-top"))
                                output.getInteger("crop-bottom") - output.getInteger("crop-top") + 1 else output.getInteger(MediaFormat.KEY_HEIGHT)
                        }
                    }
                }
                Thread.sleep(3)
            } catch (error: Exception) {
                if (!stopped.get()) fail(codecFailureCode(error, "decoder_error"), error.message ?: "视频解码失败。")
                return
            }
        }
    }

    private fun onRendered(pts: Long) {
        if (stopped.get() || paused) return
        frames++
        if (reported.compareAndSet(false, true)) {
            initialResult?.success(mapOf("textureId" to texture.id(), "width" to streamWidth, "height" to streamHeight,
                "decodedWidth" to width, "decodedHeight" to height,
                "codec" to codecName, "decoderName" to rendererName, "hardwareAccelerated" to hardware))
            initialResult = null
        }
        if (reportNextFrame.getAndSet(false) || frames % 30L == 0L) emit(mapOf("type" to "session.frame", "deviceId" to deviceId,
            "data" to mapOf("sessionId" to sessionId, "width" to streamWidth, "height" to streamHeight,
                "decodedWidth" to width, "decodedHeight" to height,
                "framesDecoded" to frames, "presentationTimeUs" to pts)))
    }

    fun setPaused(value: Boolean) = synchronized(codecLock) {
        if (stopped.get()) return@synchronized
        if (value && !paused) codec?.flush()
        paused = value
        if (!value) reportNextFrame.set(true)
    }

    fun screenshot(file: File, result: MethodChannel.Result) {
        if (stopped.get() || frames == 0L) { result.error("no_frame", "当前没有可保存的远端画面。", null); return }
        if (Build.VERSION.SDK_INT < 26) { result.error("capture_unavailable", "当前主控系统不支持此纹理截图路径。", null); return }
        val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(surface, image, { status ->
            if (status != PixelCopy.SUCCESS) { image.recycle(); result.error("capture_failed", "读取当前远端画面失败（$status）。", null); return@request }
            Thread({
                try {
                    file.parentFile?.mkdirs()
                    file.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    main.post { result.success(mapOf("status" to "completed", "localPath" to file.absolutePath)) }
                } catch (error: Exception) { main.post { result.error("save_failed", error.message, null) } }
                finally { image.recycle() }
            }, "interop-screenshot").start()
        }, main)
    }

    private fun fail(code: String, message: String) {
        main.post {
            if (stopped.get()) return@post
            if (reported.compareAndSet(false, true)) { initialResult?.error(code, message, null); initialResult = null }
            emit(mapOf("type" to "session.failed", "deviceId" to deviceId,
                "data" to mapOf("sessionId" to sessionId, "code" to code, "reason" to message)))
            close()
        }
    }

    private fun codecFailureCode(error: Exception, fallback: String): String =
        if (error is MediaCodec.CodecException) when (error.errorCode) {
            MediaCodec.CodecException.ERROR_INSUFFICIENT_RESOURCE -> "decoder_resource_exhausted"
            MediaCodec.CodecException.ERROR_RECLAIMED -> "decoder_reclaimed"
            else -> fallback
        } else fallback

    fun close() {
        if (!stopped.compareAndSet(false, true)) return
        synchronized(codecLock) {
            runCatching { socket?.close() }
            socket = null
            codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
            codec = null
        }
        surface.release()
        texture.release()
        if (reported.compareAndSet(false, true)) { initialResult?.error("cancelled", "会话已停止。", null); initialResult = null }
    }
}
