package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/** One process engine owns Dart players/channels. Activities own only UI grants.
 * Process death still ends everything; this does not provide process survival.
 */
internal object ProcessFlutterHost {
    private var engine: FlutterEngine? = null
    private var activity: WeakReference<MainActivity>? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun engine(context: Context): FlutterEngine {
        check(Looper.myLooper() == Looper.getMainLooper())
        return engine ?: FlutterEngine(context.applicationContext).also { created ->
            // The constructor registers generated plugins once. FlutterActivity
            // starts its Dart entrypoint only on the first attach.
            engine = created
            val audio = NativeAudioRuntime.get(context)
            audio.bind(::emit)
            IncomingShares.bind(this) { share -> emit(mapOf("type" to "share.platform.pending", "data" to share)) }
            EventChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/media_events")
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
                    override fun onCancel(arguments: Any?) { sink = null }
                })
            MethodChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/platform")
                .setMethodCallHandler { call, result ->
                    if (call.method == "usb.release") {
                        // This is the Rust handoff acknowledgement, not a UI
                        // operation. It must work after the host was destroyed.
                        MainActivity.releaseUsbLease(call.argument<String>("usbLeaseId"))
                        result.success(null)
                    } else if (!audio.handle(call, result)) {
                        val host = activity?.get()
                        if (host != null) host.handlePlatform(call, result)
                        else result.error("activity_unavailable", "请返回应用后执行此系统界面操作。", null)
                    }
                }
            created.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {
                    audio.stopAll()
                    sink = null
                }
                override fun onEngineWillDestroy() {
                    audio.stopAll()
                    IncomingShares.unbind(this@ProcessFlutterHost)
                    sink = null
                    if (engine === created) engine = null
                }
            })
        }
    }
    fun attach(host: MainActivity) { activity = WeakReference(host) }
    fun detach(host: MainActivity) { if (activity?.get() === host) activity = null }
    fun emit(event: Map<String, Any?>) { main.post { sink?.success(event) } }
    fun stopRequested(context: Context) {
        NativeAudioRuntime.get(context).stopAll()
        MainActivity.cancelPendingConnections()
        emit(mapOf("type" to "connections.stopped", "data" to emptyMap<String, Any>()))
    }
}
