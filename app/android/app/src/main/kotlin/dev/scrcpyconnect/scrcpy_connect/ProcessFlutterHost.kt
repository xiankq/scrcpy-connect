package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.IdentityHashMap
import java.lang.ref.WeakReference

/** 单个进程引擎拥有 Dart 播放器和通道，Activity 仅拥有界面授权；进程死亡仍结束一切，此处不保证进程存活。 */
internal object ProcessFlutterHost {
    private var engine: FlutterEngine? = null
    private var activity: WeakReference<MainActivity>? = null
    private val sinks = IdentityHashMap<FlutterEngine, EventChannel.EventSink>()
    private val environmentBridges = IdentityHashMap<FlutterEngine, WindowEnvironmentBridge>()
    private val main = Handler(Looper.getMainLooper())

    fun engine(context: Context, shellArgs: Array<String>): FlutterEngine {
        check(Looper.myLooper() == Looper.getMainLooper())
        // 仅首次创建继承 Flutter 启动参数；Activity 重新附着仍复用原引擎。
        return engine ?: FlutterEngine(context.applicationContext, shellArgs).also { created ->
            // 构造器仅注册一次生成插件；FlutterActivity 仅首次附着时启动 Dart 入口。
            engine = created
            val audio = NativeAudioRuntime.get(context)
            audio.bind(::emit)
            IncomingShares.bind(this) { share -> emit(mapOf("type" to "share.platform.pending", "data" to share)) }
            EventChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/media_events")
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sinks[created] = events }
                    override fun onCancel(arguments: Any?) { sinks.remove(created) }
                })
            MethodChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/platform")
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "usb.environment" -> result.success(UsbLeases.connections.environment())
                            "usb.beginRecovery" -> result.success(MainActivity.beginUsbRecovery(
                                call.argument<String>("expectedOwnerLeaseId"), call.argument<String>("ownerLeaseId")))
                            "usb.completeRecovery" -> result.success(UsbLeases.connections.completeRecovery(
                                call.argument<String>("ownerLeaseId")))
                            "usb.cancel" -> result.success(MainActivity.cancelUsbPermission(
                                call.argument<String>("attemptId"), call.argument<String>("ownerLeaseId")))
                            "usb.release" -> {
                                val lease = call.argument<String>("ownerLeaseId")
                                UsbLeases.connections.release(call.argument<String>("usbLeaseId"), lease)
                                result.success(mapOf("released" to true, "ownerLeaseId" to lease))
                            }
                            "window.openIndependent" -> {
                                val host = activity?.get()
                                if (host == null) result.error("activity_unavailable", "请返回应用后创建独立窗口。", null)
                                else IndependentWindowActivity.openFrom(host, call, result)
                            }
                            "window.readEnvironment" -> {
                                result.success(
                                    environmentBridges[created]?.readEnvironment()
                                        ?: activity?.get()?.readWindowEnvironment(),
                                )
                            }
                            else -> if (!audio.handle(call, result)) {
                                val host = activity?.get()
                                if (host != null) host.handlePlatform(call, result)
                                else result.error("activity_unavailable", "请返回应用后执行此系统界面操作。", null)
                            }
                        }
                    } catch (error: UsbLeaseFailure) {
                        result.error(error.code, error.message, null)
                    }
                }
            created.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {
                    MainActivity.sealUsbForRestart()
                    audio.stopAll()
                    sinks.remove(created)
                }
                override fun onEngineWillDestroy() {
                    MainActivity.sealUsbForRestart()
                    audio.stopAll()
                    IncomingShares.unbind(this@ProcessFlutterHost)
                    sinks.remove(created)
                    environmentBridges.remove(created)?.close()
                    if (engine === created) engine = null
                }
            })
        }
    }
    fun attach(host: MainActivity) {
        activity = WeakReference(host)
        engine?.let { attachEnvironmentBridge(host, it) }
    }
    fun detach(host: MainActivity) {
        if (activity?.get() === host) {
            activity = null
            engine?.let { environmentBridges.remove(it)?.close() }
        }
    }
    fun attachIndependent(host: IndependentWindowActivity, created: FlutterEngine) {
        val audio = NativeAudioRuntime.get(host.applicationContext)
        EventChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/media_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sinks[created] = events }
                override fun onCancel(arguments: Any?) { sinks.remove(created) }
            })
        MethodChannel(created.dartExecutor.binaryMessenger, "dev.scrcpyconnect/platform")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "window.readEnvironment" -> result.success(
                            environmentBridges[created]?.readEnvironment()
                                ?: host.readWindowEnvironment(),
                        )
                        "window.openIndependent" -> host.openIndependent(call, result)
                        else -> if (!audio.handle(call, result)) {
                            val mainHost = activity?.get()
                            if (mainHost != null) mainHost.handlePlatform(call, result)
                            else result.notImplemented()
                        }
                    }
                } catch (error: UsbLeaseFailure) {
                    result.error(error.code, error.message, null)
                }
            }
        created.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {
                sinks.remove(created)
            }
            override fun onEngineWillDestroy() {
                sinks.remove(created)
                environmentBridges.remove(created)?.close()
            }
        })
        attachEnvironmentBridge(host, created)
    }
    fun detachIndependent(created: FlutterEngine) {
        sinks.remove(created)
        environmentBridges.remove(created)?.close()
    }

    private fun attachEnvironmentBridge(
        host: android.app.Activity,
        created: FlutterEngine,
    ) {
        environmentBridges.remove(created)?.close()
        environmentBridges[created] = WindowEnvironmentBridge(
            host,
            created.dartExecutor.binaryMessenger,
            when (host) {
                is MainActivity -> { { host.componentName.flattenToShortString() } }
                is IndependentWindowActivity -> host::readWindowId
                else -> { { host.componentName.flattenToShortString() } }
            },
        )
    }
    fun emit(event: Map<String, Any?>) { main.post { sinks.values.toList().forEach { it.success(event) } } }
    fun stopRequested(context: Context) {
        NativeAudioRuntime.get(context).stopAll()
        MainActivity.cancelPendingConnections()
        emit(mapOf("type" to "connections.stopped", "data" to emptyMap<String, Any>()))
    }
}
