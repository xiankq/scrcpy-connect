package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

internal enum class FocusSignal(val wire: String) {
    GRANTED("granted"), TRANSIENT_LOSS("transientLoss"), PERMANENT_LOSS("permanentLoss")
}

/** 请求在放弃前拥有回调；回调在请求返回后分发。 */
internal interface FocusDriver {
    fun request(changed: (FocusSignal) -> Unit): Boolean
    fun abandon()
}

/** 全部明确混音的音源共用一份系统租约；不在租约锁内执行回调。 */
internal class FocusLeases(private val driver: FocusDriver) {
    private val lock = Any()
    private val owners = LinkedHashMap<Any, (FocusSignal) -> Unit>()
    private var generation = 0L
    private var signal = FocusSignal.PERMANENT_LOSS

    inner class Lease internal constructor(private val owner: Any) : AutoCloseable {
        fun state(): FocusSignal = synchronized(lock) {
            if (owners.containsKey(owner)) signal else FocusSignal.PERMANENT_LOSS
        }
        override fun close() {
            synchronized(lock) {
                if (owners.remove(owner) == null) return
                if (owners.isEmpty()) {
                    generation++ // 使已放弃请求排入的回调失效。
                    signal = FocusSignal.PERMANENT_LOSS
                    driver.abandon()
                }
            }
        }
    }

    fun acquire(changed: (FocusSignal) -> Unit): Lease? = synchronized(lock) {
        val owner = Any()
        owners[owner] = changed
        if (owners.size == 1) {
            val epoch = ++generation
            val granted = runCatching { driver.request { change -> signalChanged(epoch, change) } }.getOrDefault(false)
            if (!granted) {
                owners.remove(owner)
                generation++
                signal = FocusSignal.PERMANENT_LOSS
                runCatching { driver.abandon() }
                return null
            }
            signal = FocusSignal.GRANTED
        }
        Lease(owner)
    }

    private fun signalChanged(epoch: Long, change: FocusSignal) {
        val callbacks = synchronized(lock) {
            if (epoch != generation || owners.isEmpty()) return
            signal = change
            val result = owners.values.toList()
            if (change == FocusSignal.PERMANENT_LOSS) {
                owners.clear()
                generation++
                runCatching { driver.abandon() }
            }
            result
        }
        callbacks.forEach { callback -> runCatching { callback(change) } }
    }
}

/** 应用共享此所有者，各播放器不单独申请；它不会启动前台服务。Android 15 及以上仅允许前台应用或符合条件的前台服务申请音频焦点，见 https://developer.android.com/media/optimize/audio-focus。 */
class AudioFocusController(context: Context) {
    private val leases = FocusLeases(AndroidFocusDriver(context.applicationContext))
    internal fun acquire(changed: (FocusSignal) -> Unit): FocusLeases.Lease? = leases.acquire(changed)
}

private class AndroidFocusDriver(context: Context) : FocusDriver {
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var request: AudioFocusRequest? = null
    private var legacy: AudioManager.OnAudioFocusChangeListener? = null

    override fun request(changed: (FocusSignal) -> Unit): Boolean {
        val listener = AudioManager.OnAudioFocusChangeListener { value ->
            val signal = when (value) {
                AudioManager.AUDIOFOCUS_GAIN -> FocusSignal.GRANTED
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> FocusSignal.TRANSIENT_LOSS
                AudioManager.AUDIOFOCUS_LOSS -> FocusSignal.PERMANENT_LOSS
                else -> null
            }
            // 包括旧接口在内的所有回调都排队，不能在 requestAudioFocus 内部或持有租约锁时调用播放器。
            if (signal != null) main.post { changed(signal) }
        }
        val result = if (Build.VERSION.SDK_INT >= 26) {
            val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setWillPauseWhenDucked(true)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(listener, main).build()
            request = focus
            manager.requestAudioFocus(focus)
        } else {
            legacy = listener
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    override fun abandon() {
        if (Build.VERSION.SDK_INT >= 26) {
            request?.let { manager.abandonAudioFocusRequest(it) }
            request = null
        } else {
            @Suppress("DEPRECATION")
            legacy?.let { manager.abandonAudioFocus(it) }
            legacy = null
        }
    }
}
