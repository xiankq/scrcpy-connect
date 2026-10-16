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

/** A request owns its callback until abandon. Callbacks are dispatched after request returns. */
internal interface FocusDriver {
    fun request(changed: (FocusSignal) -> Unit): Boolean
    fun abandon()
}

/** One system lease for every explicitly mixed source; callbacks never run under the lease lock. */
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
                    generation++ // Invalidate callbacks already queued by the abandoned request.
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

/**
 * Shared by the app, not one request per player. This never starts a foreground service.
 * Android 15+ rejects the real request unless the app is topmost or has an eligible FGS:
 * https://developer.android.com/media/optimize/audio-focus
 */
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
            // Always queue, including legacy callbacks; no player callback can
            // run inside requestAudioFocus or while the lease lock is held.
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
