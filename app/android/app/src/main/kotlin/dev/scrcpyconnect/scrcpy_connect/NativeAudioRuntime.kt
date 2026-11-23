package dev.scrcpyconnect.scrcpy_connect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 仅提供操作系统适配；PCM、播放器状态和组合暂停原因归 Dart 所有。 */
class NativeAudioRuntime private constructor(private val app: Context) {
    companion object {
        @Volatile private var instance: NativeAudioRuntime? = null
        fun get(context: Context): NativeAudioRuntime = instance ?: synchronized(this) {
            instance ?: NativeAudioRuntime(context.applicationContext).also { instance = it }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val focus = AudioFocusController(app)
    private val owners = AudioPlatformOwnership()
    private var lease: FocusLeases.Lease? = null
    private var emitter: ((Map<String, Any?>) -> Unit)? = null
    private var backgroundGeneration = 0L
    private var pendingBackground: MethodChannel.Result? = null
    private var noisyRegistered = false
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                val epoch = owners.epoch ?: return
                releaseLease()
                emit("audio.platform.focus", mapOf("epoch" to epoch, "signal" to "noisy"))
            }
        }
    }

    fun bind(callback: (Map<String, Any?>) -> Unit) { emitter = callback }
    private fun emit(type: String, data: Map<String, Any?>) {
        main.post { emitter?.invoke(mapOf("type" to type, "data" to data)) }
    }
    fun visible(owner: Any, value: Boolean) {
        if (owners.visible(owner, value)) emit("audio.platform.visibility", mapOf("visible" to owners.visible))
    }
    fun detach(owner: Any) = visible(owner, false)

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("audio.platform.")) return false
        check(Looper.myLooper() == Looper.getMainLooper())
        try {
            if (call.method == "audio.platform.state") {
                result.success(mapOf("visible" to owners.visible,
                    "mediaPlaybackReady" to ConnectionService.mediaPlaybackReady,
                    "sameEngineOwnership" to true, "processSurvivalGuaranteed" to false))
                return true
            }
            val owner = call.argument<String>("ownerId")
            require(owner != null && owner.length in 1..128) { "Missing audio output owner" }
            when (call.method) {
                "audio.platform.focus.acquire" -> {
                    if (!owners.claim(owner)) {
                        result.error("audio_owner_busy", "另一个声音输出仍在释放焦点，请稍后重试。", null)
                    } else if (lease != null) {
                        result.success(mapOf("granted" to (lease?.state() == FocusSignal.GRANTED), "epoch" to owners.epoch))
                    } else {
                        val epoch = owners.nextEpoch()
                        lease = focus.acquire { signal ->
                            if (owners.epoch != epoch) return@acquire
                            if (signal == FocusSignal.PERMANENT_LOSS) releaseLease()
                            emit("audio.platform.focus", mapOf("epoch" to epoch, "signal" to signal.wire))
                        }
                        if (lease == null) owners.clearEpoch(epoch) else {
                            try { registerNoisy() } catch (error: Exception) { releaseLease(); throw error }
                        }
                        result.success(mapOf("granted" to (lease != null), "epoch" to epoch))
                        releaseUnusedOwner()
                    }
                }
                "audio.platform.focus.release" -> {
                    val epoch = call.argument<Number>("epoch")?.toLong()
                    val matches = owners.owner == owner && epoch != null && owners.epoch == epoch
                    if (matches) releaseLease()
                    result.success(mapOf("released" to matches))
                }
                "audio.platform.background" -> background(owner, call.argument<Boolean>("enabled") == true, result)
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("audio_platform_failed", error.message ?: "系统声音操作未完成。", null)
        }
        return true
    }

    private fun registerNoisy() {
        if (noisyRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") app.registerReceiver(noisy, filter)
        noisyRegistered = true
    }
    private fun releaseLease() {
        lease?.close(); lease = null
        owners.epoch?.let { owners.clearEpoch(it) }
        if (noisyRegistered) {
            app.unregisterReceiver(noisy)
            noisyRegistered = false
        }
        releaseUnusedOwner()
    }
    private fun releaseUnusedOwner() { owners.releaseIfUnused() }

    private fun background(owner: String, enabled: Boolean, result: MethodChannel.Result) {
        if ((enabled && !owners.claim(owner)) || (!enabled && owners.owner != null && owners.owner != owner)) {
            result.error("audio_owner_busy", "后台声音资格不属于此输出。", null)
            return
        }
        val generation = ++backgroundGeneration
        pendingBackground?.error("cancelled", "后台声音请求已被更新。", null)
        pendingBackground = null
        owners.background = enabled
        try { ConnectionService.keepAudio(app, enabled) } catch (error: Exception) {
            owners.background = false
            stopBackgroundAudio()
            releaseUnusedOwner()
            result.error("audio_background_unavailable", error.message, null)
            return
        }
        if (!enabled) {
            releaseUnusedOwner()
            result.success(mapOf("enabled" to false, "ready" to false))
            return
        }
        pendingBackground = result
        val deadline = SystemClock.uptimeMillis() + 2500
        fun confirm() {
            if (generation != backgroundGeneration || pendingBackground !== result) return
            if (ConnectionService.mediaPlaybackReady) {
                pendingBackground = null
                result.success(mapOf("enabled" to true, "ready" to true, "mediaPlaybackReady" to true))
            } else if (SystemClock.uptimeMillis() >= deadline) {
                pendingBackground = null
                owners.background = false
                stopBackgroundAudio()
                releaseUnusedOwner()
                result.error("audio_background_unavailable", "系统尚未确认媒体前台服务。", null)
            } else main.postDelayed({ confirm() }, 25)
        }
        confirm()
    }
    fun foregroundChanged() {
        emit("audio.platform.background", mapOf("ready" to ConnectionService.mediaPlaybackReady,
            "enabled" to owners.background, "ownerId" to owners.owner))
    }
    private fun stopBackgroundAudio() {
        try {
            ConnectionService.keepAudio(app, false)
        } catch (error: Exception) {
            Log.w("Interconnect", "audio.stop_background: ${error.javaClass.simpleName}")
        }
    }
    /** 仅用于明确停止或 Dart 引擎重启，Activity 分离时不得调用。 */
    fun stopAll() {
        backgroundGeneration++
        pendingBackground?.error("cancelled", "声音活动已停止。", null)
        pendingBackground = null
        owners.background = false
        releaseLease()
        stopBackgroundAudio()
    }
}
