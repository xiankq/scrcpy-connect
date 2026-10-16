package dev.scrcpyconnect.scrcpy_connect

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

internal enum class PcmPlayState { STOPPED, PAUSED, PLAYING }
internal interface PcmSink {
    val playState: PcmPlayState
    val nativePlayState: Int
    val playbackHead: Long
    fun play()
    fun pause()
    fun flush()
    fun release()
    fun volume(value: Float): Boolean
    fun write(data: ByteArray, offset: Int, count: Int): Int
}

/** Serializes short, nonblocking hardware operations against pause/close. No PCM queue is retained. */
internal class PcmPlayback(private val failed: (Exception) -> Unit = {}) {
    private val lock = Any()
    private var sink: PcmSink? = null
    private var closed = false
    private var manualPaused = false
    private var backgroundPaused = false
    private var focus = FocusSignal.PERMANENT_LOSS
    private var epoch = 0L
    private var revision = 0L
    private var written = 0L
    private var dropped = 0L
    private var flushes = 0L

    fun generation(): Long = synchronized(lock) { epoch }
    fun writtenBytes(): Long = synchronized(lock) { written }
    fun attach(output: PcmSink): Boolean = synchronized(lock) {
        if (closed) { output.release(); return false }
        check(sink == null) { "声音输出已经初始化。" }
        sink = output
        revision++
        applyPlayback()
        true
    }
    private fun allowed() = !closed && !manualPaused && !backgroundPaused && focus == FocusSignal.GRANTED
    private fun <T> hardware(operation: () -> T): T = try {
        operation()
    } catch (error: Exception) {
        close()
        // Release the player's socket/focus lease before propagating the
        // original error. One failed cleanup must not replace that error.
        runCatching { failed(error) }
        throw error
    }
    private fun applyPlayback() {
        val output = sink ?: return
        hardware {
            if (allowed()) {
                if (output.playState != PcmPlayState.PLAYING) output.play()
                check(output.playState == PcmPlayState.PLAYING) { "系统未开始声音播放。" }
            } else {
                if (output.playState != PcmPlayState.PAUSED) {
                    output.pause()
                    output.flush()
                    flushes++
                }
                check(output.playState == PcmPlayState.PAUSED) { "系统未暂停声音播放。" }
            }
        }
    }
    private fun update(change: () -> Unit): Map<String, Any?> = synchronized(lock) {
        if (closed) return snapshot()
        val before = allowed()
        revision++
        change()
        if (before != allowed()) epoch++
        applyPlayback()
        snapshot()
    }
    fun manualPause(paused: Boolean) = update { manualPaused = paused }
    fun backgroundPause(paused: Boolean) = update { backgroundPaused = paused }
    fun focus(change: FocusSignal) = update { focus = change }

    /** Returns consumed bytes, including deliberately discarded PCM. Zero means hardware backpressure. */
    fun consume(data: ByteArray, offset: Int, count: Int, packetEpoch: Long): Int = synchronized(lock) {
        require(offset >= 0 && count >= 0 && offset <= data.size - count && count % 4 == 0)
        val output = sink
        if (!allowed() || output == null || packetEpoch != epoch) {
            dropped += count
            return count
        }
        val countWritten = hardware {
            val result = output.write(data, offset, minOf(count, 4096))
            check(result >= 0 && result <= minOf(count, 4096) && result % 4 == 0) {
                "声音输出中断（$result）。"
            }
            result
        }
        written += countWritten
        countWritten
    }
    fun volume(value: Float, muted: Boolean): Boolean = synchronized(lock) {
        require(value.isFinite() && value in 0f..1f)
        !closed && sink?.volume(if (muted) 0f else value) == true
    }
    fun status(): Map<String, Any?> = synchronized(lock) { snapshot() }
    private fun snapshot(): Map<String, Any?> {
        val output = sink
        val state = when {
            closed -> "stopped"
            output == null -> "starting"
            output.playState == PcmPlayState.PLAYING -> "playing"
            output.playState == PcmPlayState.PAUSED -> "paused"
            else -> "stopped"
        }
        return mapOf(
            "applied" to (!closed && output != null && (state == "playing" || state == "paused")),
            "playState" to state, "manualPaused" to manualPaused,
            "focusPaused" to (focus != FocusSignal.GRANTED), "backgroundPaused" to backgroundPaused,
            "focusState" to focus.wire, "trackPlayState" to output?.nativePlayState,
            "playbackHeadPosition" to (output?.playbackHead ?: 0L),
            "bytesWritten" to written, "droppedBytes" to dropped, "flushCount" to flushes,
            "closed" to closed, "revision" to revision
        )
    }
    fun close(): Unit = synchronized(lock) {
        if (closed) return
        closed = true
        revision++
        epoch++
        val output = sink
        sink = null
        if (output != null) {
            runCatching { output.pause() }
            runCatching { output.flush() }
            runCatching { output.release() }
        }
    }
}

private class AndroidPcmSink(private val track: AudioTrack) : PcmSink {
    override val playState: PcmPlayState get() = when (track.playState) {
        AudioTrack.PLAYSTATE_PLAYING -> PcmPlayState.PLAYING
        AudioTrack.PLAYSTATE_PAUSED -> PcmPlayState.PAUSED
        else -> PcmPlayState.STOPPED
    }
    override val nativePlayState: Int get() = track.playState
    override val playbackHead: Long get() = track.playbackHeadPosition.toLong() and 0xffff_ffffL
    override fun play() = track.play()
    override fun pause() = track.pause()
    override fun flush() = track.flush()
    override fun release() = track.release()
    override fun volume(value: Float) = track.setVolume(value) == AudioTrack.SUCCESS
    override fun write(data: ByteArray, offset: Int, count: Int): Int =
        track.write(data, offset, count, AudioTrack.WRITE_NON_BLOCKING)
}

/** One PCM player per remote device. Android mixes sources sharing the app's single focus lease. */
class RemoteAudioPlayer(
    private val sourceId: String,
    private val deviceId: String?,
    private val focusController: AudioFocusController,
    private val emit: (Map<String, Any?>) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    private val startupPending = AtomicBoolean(false)
    private val resources = Any()
    private val playback = PcmPlayback { error -> fail("audio_failed", error.message ?: "声音输出已中断。") }
    private var socket: Socket? = null
    private var lease: FocusLeases.Lease? = null
    private var pending: MethodChannel.Result? = null // Main thread only.
    private val timeout = Runnable { fail("audio_timeout", "尚未收到可播放的设备声音。") }

    fun start(port: Int, token: String, result: MethodChannel.Result) {
        check(Looper.myLooper() == Looper.getMainLooper())
        check(started.compareAndSet(false, true) && !closed.get()) { "声音播放器已启动或已停止。" }
        pending = result
        startupPending.set(true)
        main.postDelayed(timeout, 20_000)
        val acquired = focusController.acquire(::focusChanged)
        if (acquired == null) {
            fail("audio_focus_denied", "系统未授予声音焦点；Android 15 及以上需要应用位于前台或正在运行允许的媒体前台服务。")
            return
        }
        synchronized(resources) { lease = acquired }
        playback.focus(acquired.state())
        Thread({ readPcm(port, token) }, "interop-audio-$sourceId").start()
    }

    private fun readPcm(port: Int, token: String) {
        try {
            require(token.length == 64 && token.all { it in '0'..'9' || it in 'a'..'f' })
            require(port in 1..65535)
            val connection = Socket()
            synchronized(resources) {
                if (closed.get()) { connection.close(); return }
                socket = connection
            }
            connection.connect(InetSocketAddress("127.0.0.1", port), 5000)
            connection.tcpNoDelay = true
            connection.getOutputStream().apply { write((token + "\n").toByteArray(Charsets.US_ASCII)); flush() }
            val format = AudioFormat.Builder().setSampleRate(48_000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
            val minimum = AudioTrack.getMinBufferSize(48_000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            require(minimum > 0) { "此设备未能初始化声音输出。" }
            val player = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setAudioFormat(format).setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(maxOf(minimum * 2, 8192)).build()
            if (player.state != AudioTrack.STATE_INITIALIZED) {
                player.release()
                error("此设备未能初始化声音输出。")
            }
            if (!playback.attach(AndroidPcmSink(player))) return
            val input = DataInputStream(connection.getInputStream())
            while (!closed.get()) {
                // Capture before the blocking read: a pause/resume during a
                // partial packet must not make that stale packet playable.
                val epoch = playback.generation()
                val beforeWritten = playback.writtenBytes()
                val pts = input.readLong()
                val size = input.readInt()
                require(size in 4..(1024 * 1024) && size % 4 == 0) { "设备声音数据格式无效。" }
                val data = ByteArray(size)
                input.readFully(data)
                var offset = 0
                while (offset < size && !closed.get()) {
                    val consumed = playback.consume(data, offset, size - offset, epoch)
                    offset += consumed
                    if (consumed == 0) Thread.sleep(2)
                }
                if (startupPending.get() && playback.writtenBytes() > beforeWritten) main.post {
                    if (closed.get() || playback.generation() != epoch || playback.status()["playState"] != "playing") return@post
                    val first = pending ?: return@post
                    pending = null
                    startupPending.set(false)
                    main.removeCallbacks(timeout)
                    first.success(receipt() + mapOf("sampleRate" to 48_000, "channels" to 2, "presentationTimeUs" to pts))
                }
            }
        } catch (error: Exception) {
            if (!closed.get()) fail("audio_failed", error.message ?: "声音已中断。")
        } finally { releaseResources() }
    }

    fun volume(value: Float, muted: Boolean) = playback.volume(value, muted)
    fun setPaused(paused: Boolean): Map<String, Any?> = receipt(playback.manualPause(paused))
    fun setBackgroundPaused(paused: Boolean): Map<String, Any?> = try {
        receipt(playback.backgroundPause(paused))
    } catch (error: Exception) {
        // onStart/onStop also invoke this method, outside a MethodChannel RPC.
        // The hardware failure callback already closed the track and lease.
        receipt() + mapOf("error" to "audio_failed", "message" to (error.message ?: "声音输出已中断。"))
    }
    fun status(): Map<String, Any?> = receipt()
    private fun receipt(state: Map<String, Any?> = playback.status()): Map<String, Any?> =
        state + mapOf("sourceId" to sourceId, "deviceId" to deviceId)

    private fun focusChanged(change: FocusSignal) {
        if (closed.get()) return
        try {
            val state = playback.focus(change)
            if (change == FocusSignal.PERMANENT_LOSS) {
                fail("audio_focus_lost", "其他应用已接管声音，请手动重新开启设备声音。")
            } else if (!closed.get()) {
                emit(mapOf("type" to "audio.focus", "deviceId" to deviceId,
                    "data" to (receipt(state) + mapOf("reason" to if (change == FocusSignal.GRANTED) "focus_gain" else "focus_transient_loss"))))
            }
        } catch (error: Exception) { fail("audio_failed", error.message ?: "声音焦点切换失败。") }
    }

    private fun fail(code: String, message: String) {
        if (!closed.compareAndSet(false, true)) return
        startupPending.set(false)
        releaseResources()
        main.post {
            main.removeCallbacks(timeout)
            pending?.error(code, message, null)
            pending = null
            emit(mapOf("type" to "audio.failed", "deviceId" to deviceId,
                "data" to (receipt() + mapOf("code" to code, "message" to message, "reason" to code))))
        }
    }
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        startupPending.set(false)
        releaseResources()
        main.post {
            main.removeCallbacks(timeout)
            pending?.error("cancelled", "声音播放已停止。", null)
            pending = null
        }
    }
    private fun releaseResources() {
        playback.close()
        val resourcesToClose = synchronized(resources) {
            val owned = Pair(socket, lease)
            socket = null
            lease = null
            owned
        }
        runCatching { resourcesToClose.first?.close() }
        runCatching { resourcesToClose.second?.close() }
    }
}
