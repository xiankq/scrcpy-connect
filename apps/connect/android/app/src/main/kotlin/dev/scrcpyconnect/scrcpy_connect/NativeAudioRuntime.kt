package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference


/** Same-process owner. Process death never recreates players, focus, tokens or remote capture. */
class NativeAudioRuntime private constructor(private val app: Context) {
    companion object {
        @Volatile private var instance: NativeAudioRuntime? = null
        fun get(context: Context): NativeAudioRuntime = instance ?: synchronized(this) {
            instance ?: NativeAudioRuntime(context.applicationContext).also { instance = it }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val focus = AudioFocusController(app)
    private var boundOwner: WeakReference<Any>? = null
    private var emitter: ((Map<String, Any?>) -> Unit)? = null
    private var desiredBackground = false
    private val replies = linkedMapOf<String, DetachedResult>()
    private val players = linkedMapOf<String, RemoteAudioPlayer>()
    private val ready = mutableSetOf<String>()
    private val ownership = AudioSessionOwnership { receipt ->
        emit(mapOf("type" to "audio.focus", "deviceId" to receipt["deviceId"],
            "data" to (receipt + mapOf("reason" to "background_policy"))))
    }

    /** The relay drops the old engine's MethodChannel.Result on detach. */
    private class DetachedResult(owner: Any, private var target: MethodChannel.Result?, private val completed: (Any?) -> Any?) : MethodChannel.Result {
        private val owner = WeakReference(owner)
        fun detach(old: Any) { if (owner.get() === old) target = null }
        override fun success(result: Any?) { val reply = target; target = null; val receipt = completed(result); reply?.success(receipt) }
        override fun error(code: String, message: String?, details: Any?) { val reply = target; target = null; reply?.error(code, message, details) }
        override fun notImplemented() { val reply = target; target = null; reply?.notImplemented() }
    }

    fun bind(owner: Any, callback: (Map<String, Any?>) -> Unit) { boundOwner = WeakReference(owner); emitter = callback }
    fun unbindEvents(owner: Any) { if (boundOwner?.get() === owner) { boundOwner = null; emitter = null } }
    fun detach(owner: Any) {
        ownership.setVisible(owner, false)
        replies.values.forEach { it.detach(owner) }
        if (boundOwner?.get() === owner) { boundOwner = null; emitter = null }
    }
    fun visible(owner: Any, visible: Boolean) { ownership.setVisible(owner, visible) }
    fun policy(allowed: Boolean): Map<String, Any?> {
        desiredBackground = allowed
        updateService()
        foregroundChanged()
        return mapOf("backgroundAllowed" to allowed)
    }
    private fun updateService() { ConnectionService.keepAudio(app, desiredBackground && !ownership.empty()) }
    fun foregroundChanged() { ownership.backgroundAllowed = desiredBackground && ConnectionService.mediaPlaybackReady }
    private fun emit(event: Map<String, Any?>) {
        main.post {
            if (event["type"] == "audio.failed") {
                val data = event["data"] as? Map<*, *>
                val id = data?.get("sourceId") as? String
                players.remove(id); ownership.remove(id); replies.remove(id); ready.remove(id)
                runCatching { updateService() }
            }
            if (boundOwner?.get() != null) emitter?.invoke(event)
        }
    }
    fun start(owner: Any, id: String, deviceId: String?, port: Int, token: String, result: MethodChannel.Result) {
        check(Looper.myLooper() == Looper.getMainLooper())
        val existing = players[id]
        if (existing != null) {
            val state = existing.status()
            if (state["applied"] == true) result.success(state)
            else result.error("audio_start_pending", "设备声音仍在准备中，请等待原请求。", null)
            return
        }
        val reply = DetachedResult(owner, result) { receipt ->
            if (players.containsKey(id)) {
                ready.add(id)
                val data = (receipt as? Map<*, *>)?.entries?.mapNotNull { (key, value) -> (key as? String)?.let { it to value } }?.toMap().orEmpty()
                val confirmed = data + mapOf("nativeReady" to true)
                emit(mapOf("type" to "audio.ready", "deviceId" to deviceId, "data" to confirmed))
                confirmed
            } else receipt
        }; replies[id] = reply
        val player = RemoteAudioPlayer(id, deviceId, focus, ::emit)
        players[id] = player
        ownership.add(id, object : OwnedAudio {
            override fun background(paused: Boolean) = player.setBackgroundPaused(paused)
            override fun status() = player.status()
            override fun close() = player.close()
        })
        try { updateService() } catch (error: Exception) {
            stop(id); reply.error("audio_background_unavailable", error.message, null); return
        }
        val deadline = android.os.SystemClock.uptimeMillis() + 5000
        fun launchWhenEligible() {
            if (players[id] !== player) return
            if (ownership.isVisible() || (desiredBackground && ConnectionService.mediaPlaybackReady)) {
                foregroundChanged()
                player.start(port, token, reply)
            } else if (!desiredBackground) {
                // A foreground start may have become background while the
                // remote stream was preparing. Keep it paused, never auto-play.
                player.start(port, token, reply)
            } else if (android.os.SystemClock.uptimeMillis() >= deadline) {
                stop(id); reply.error("audio_background_unavailable", "媒体前台服务尚未就绪，没有开始声音播放。", null)
            } else main.postDelayed({ launchWhenEligible() }, 25)
        }
        launchWhenEligible()
    }
    fun stop(id: String?) { players.remove(id); ownership.remove(id); replies.remove(id); ready.remove(id); updateService() }
    fun stopAll() { players.clear(); ownership.stopAll(); replies.clear(); ready.clear(); updateService() }
    fun paused(id: String?, paused: Boolean): Map<String, Any?> = player(id).setPaused(paused)
    fun volume(id: String?, volume: Float, muted: Boolean) = player(id).volume(volume, muted)
    fun status(id: String?): Map<String, Any?> = player(id).status()
    fun attach(): Map<String, Any?> = mapOf("sources" to players.map { (id, player) -> player.status() + mapOf("nativeReady" to ready.contains(id)) }, "sameProcess" to true)
    private fun player(id: String?) = players[id] ?: error("设备声音已经停止。")
}
