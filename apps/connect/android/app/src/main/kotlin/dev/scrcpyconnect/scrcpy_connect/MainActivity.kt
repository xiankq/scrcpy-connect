package dev.scrcpyconnect.scrcpy_connect

import android.app.AlertDialog
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

private object UsbLeases {
    val connections = mutableMapOf<String, UsbDeviceConnection>()
}

class MainActivity : FlutterActivity() {
    companion object {
        private var current: java.lang.ref.WeakReference<MainActivity>? = null
        fun cancelPendingConnections() { current?.get()?.cancelPendingConnectionsAndMedia() }
    }
    private val main = Handler(Looper.getMainLooper())
    private val documents by lazy { PlatformDocuments(this) }
    private val decoders = mutableMapOf<String, RemoteVideoDecoder>()
    private val audio by lazy { NativeAudioRuntime.get(applicationContext) }
    private var events: EventChannel.EventSink? = null
    private var registry: io.flutter.view.TextureRegistry? = null
    private var pendingUsb: MethodChannel.Result? = null
    private var pendingDevice: UsbDevice? = null
    private var pendingUsbAttempt: String? = null
    private var usbChooser: AlertDialog? = null
    private var usbGeneration = 0L
    private val usbAction get() = "$packageName.USB_PERMISSION"
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != usbAction || intent.getLongExtra("generation", -1) != usbGeneration) return
            val result = pendingUsb ?: return
            val device = pendingDevice
            pendingUsb = null
            pendingDevice = null
            pendingUsbAttempt = null
            if (device == null || !(getSystemService(USB_SERVICE) as UsbManager).hasPermission(device)) {
                result.error("permission_denied", "尚未允许主控应用访问 USB 设备。", null)
            } else openUsb(device, result)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        current = java.lang.ref.WeakReference(this)
        registry = flutterEngine.renderer
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.scrcpyconnect/media_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink; bindNativeEvents() }
                override fun onCancel(arguments: Any?) { events = null; audio.unbindEvents(this@MainActivity); IncomingShares.unbind(this@MainActivity) }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.scrcpyconnect/platform")
            .setMethodCallHandler(::handlePlatform)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(usbReceiver, IntentFilter(usbAction), RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(usbReceiver, IntentFilter(usbAction))
        bindNativeEvents()
        acceptIncoming(intent, false)
    }

    override fun onStart() {
        super.onStart()
        audio.visible(this, true)
        DiscoveryNetwork.acquire(this, "activity")
    }

    override fun onStop() {
        audio.visible(this, false)
        DiscoveryNetwork.release("activity")
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptIncoming(intent, true)
    }

    private fun emit(event: Map<String, Any?>) { main.post { events?.success(event) } }

    private fun bindNativeEvents() {
        val activity = java.lang.ref.WeakReference(this)
        audio.bind(this) { event -> activity.get()?.emit(event) }
        IncomingShares.bind(this) { share -> activity.get()?.emit(mapOf("type" to "share.platform.pending", "data" to share)) }
    }

    private fun acceptIncoming(intent: Intent?, renewed: Boolean) {
        val caller = if (Build.VERSION.SDK_INT >= 35) runCatching { if (renewed) currentCaller else initialCaller }.getOrNull() else null
        IncomingShares.accept(applicationContext, intent) { uri ->
            Build.VERSION.SDK_INT < 35 || runCatching {
                caller?.checkContentUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            }.getOrDefault(false)
        }
    }

    private fun cancelPendingConnectionsAndMedia() {
        usbGeneration++
        usbChooser?.dismiss()
        usbChooser = null
        pendingUsb?.error("cancelled", "已停止连接。", null)
        pendingUsb = null
        pendingDevice = null
        pendingUsbAttempt = null
        decoders.values.forEach { it.close() }
        decoders.clear()
        audio.stopAll()
        emit(mapOf("type" to "connections.stopped", "data" to emptyMap<String,Any>()))
    }

    private fun handlePlatform(call: MethodCall, result: MethodChannel.Result) {
        try {
            val documentArguments = (call.arguments as? Map<*, *>)?.entries?.mapNotNull { entry ->
                (entry.key as? String)?.let { it to entry.value }
            }?.toMap().orEmpty()
            if (documents.handle(call.method, documentArguments, result)) return
            if (IncomingShares.handle(applicationContext, this, call, result)) return
            when (call.method) {
                "audio.start" -> {
                    val id = call.argument<String>("sourceId") ?: error("Missing audio source")
                    val port = call.argument<Number>("audioPort")?.toInt() ?: error("Missing audio port")
                    val token = call.argument<String>("audioToken") ?: error("Missing audio token")
                    audio.start(this, id, call.argument<String>("deviceId"), port, token, result)
                }
                "audio.attach" -> result.success(audio.attach())
                "audio.stop" -> { audio.stop(call.argument<String>("sourceId")); result.success(null) }
                "audio.pause", "audio.resume" -> {
                    result.success(audio.paused(call.argument<String>("sourceId"), call.method == "audio.pause"))
                }
                "audio.status" -> {
                    result.success(audio.status(call.argument<String>("sourceId")))
                }
                "audio.policy" -> {
                    result.success(audio.policy(call.argument<Boolean>("backgroundAllowed") == true))
                }
                "audio.volume" -> {
                    val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                    val muted = call.argument<Boolean>("muted") ?: false
                    if (!audio.volume(call.argument<String>("sourceId"), volume,muted)) result.error("audio_volume_failed", "无法调整此设备声音。", null)
                    else result.success(mapOf("applied" to true, "volume" to volume, "muted" to muted))
                }
                "video.start" -> {
                    val id = call.argument<String>("sessionId") ?: error("Missing session id")
                    val port = call.argument<Number>("videoPort")?.toInt() ?: error("Missing video port")
                    val token = call.argument<String>("videoToken") ?: error("Missing video token")
                    val videoCodec = call.argument<String>("codec") ?: "h264"
                    if (!RemoteVideoDecoder.mimeTypes.containsKey(videoCodec)) { result.error("codec_unavailable", "此媒体适配尚不支持所选编码器。", null); return }
                    decoders.remove(id)?.close()
                    val decoder = RemoteVideoDecoder(id, call.argument<String>("deviceId"), registry!!, ::emit, videoCodec)
                    decoders[id] = decoder
                    decoder.start(port, token, result)
                }
                "video.capabilities" -> result.success(RemoteVideoDecoder.capabilities())
                "video.stop" -> { decoders.remove(call.argument<String>("sessionId"))?.close(); result.success(null) }
                "video.pause" -> {
                    val decoder = decoders[call.argument<String>("sessionId")]
                    if (decoder == null) result.error("no_session", "当前控制会话已结束。", null)
                    else { decoder.setPaused(call.argument<Boolean>("paused") ?: true); result.success(null) }
                }
                "video.screenshot" -> {
                    val id = call.argument<String>("sessionId")
                    val decoder = decoders[id]
                    if (decoder == null) { result.error("no_session", "请先打开要截图的远控会话。", null); return }
                    decoder.screenshot(File(filesDir, "screenshots/${UUID.randomUUID()}.png"), result)
                }
                "usb.authorize" -> authorizeUsb(call, result)
                "usb.release" -> {
                    UsbLeases.connections.remove(call.argument<String>("usbLeaseId"))?.close()
                    result.success(null)
                }
                "usb.cancel" -> {
                    val attempt = call.argument<String>("attemptId")
                    if (attempt != null && attempt == pendingUsbAttempt) {
                        usbGeneration++
                        usbChooser?.dismiss()
                        usbChooser = null
                        pendingUsb?.error("cancelled", "已取消 USB 连接。", null)
                        pendingUsb = null
                        pendingDevice = null
                        pendingUsbAttempt = null
                    }
                    result.success(null)
                }
                "background.status" -> result.success(backgroundStatus())
                "background.request" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) {
                        if (call.argument<Boolean>("askNotificationPermission") == true && Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2102)
                        }
                    }
                    ConnectionService.keepConnections(this, enabled)
                    result.success(backgroundStatus() + mapOf("requested" to enabled))
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) { result.error("platform_error", error.message ?: "系统操作未完成。", null) }
    }

    private fun backgroundStatus(): Map<String, Any> {
        val allowed = Build.VERSION.SDK_INT < 33 || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        return mapOf("supported" to true, "running" to ConnectionService.running,
            "connectionRequested" to ConnectionService.connectionRequested,
            "audioRequested" to ConnectionService.audioRequested,
            "notificationPermission" to allowed, "canRequest" to (!allowed || !ConnectionService.running || !ConnectionService.connectionRequested),
            "title" to (if (ConnectionService.running) "设备活动正在保持" else "后台保持尚未启动"),
            "reason" to (if (!allowed) "尚未允许显示连接通知。系统任务管理器仍可停止活动；允许通知后，可从通知栏返回或停止连接。"
                else if (ConnectionService.running) "已启动系统前台服务。后台活动仍受系统电量与网络策略影响。"
                else "可在有设备活动时启用后台保持；不会自动重启已主动停止的连接。"))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2102) emit(mapOf("type" to "background.changed", "data" to backgroundStatus()))
    }

    private fun authorizeUsb(call: MethodCall, result: MethodChannel.Result) {
        if (pendingUsb != null) { result.error("permission_pending", "已有一个 USB 授权请求正在等待。", null); return }
        val manager = getSystemService(USB_SERVICE) as UsbManager
        val devices = manager.deviceList.values.filter { device ->
            (0 until device.interfaceCount).any { index ->
                val item = device.getInterface(index)
                item.interfaceClass == 255 && item.interfaceSubclass == 66 && item.interfaceProtocol == 1
            }
        }
        if (devices.isEmpty()) { result.error("usb_not_found", "未识别到 ADB 设备，请检查数据线、USB 角色和被控手机的 USB 调试。", null); return }
        val explicit = call.argument<String>("usbDeviceId")
        val selected = explicit?.let { id -> devices.firstOrNull { it.deviceName == id } }
        if (explicit != null && selected == null) { result.error("usb_removed", "所选 USB 设备已断开。", null); return }
        val generation = ++usbGeneration
        pendingUsb = result
        pendingUsbAttempt = call.argument<String>("attemptId")
        if (selected != null || devices.size == 1) requestUsbPermission(selected ?: devices.first(), generation)
        else {
            usbChooser = AlertDialog.Builder(this).setTitle("选择被控手机")
                .setItems(devices.map { it.productName ?: it.deviceName }.toTypedArray()) { _, index ->
                    usbChooser = null
                    requestUsbPermission(devices[index], generation)
                }
                .setOnCancelListener {
                    if (generation == usbGeneration) {
                        pendingUsb?.error("cancelled", "已取消选择 USB 设备。", null)
                        pendingUsb = null
                        pendingDevice = null
                        pendingUsbAttempt = null
                    }
                    usbChooser = null
                }.create()
            usbChooser?.show()
        }
    }

    private fun requestUsbPermission(device: UsbDevice, generation: Long) {
        if (generation != usbGeneration) return
        val result = pendingUsb ?: return
        val manager = getSystemService(USB_SERVICE) as UsbManager
        if (manager.hasPermission(device)) {
            pendingUsb = null
            pendingDevice = null
            pendingUsbAttempt = null
            openUsb(device, result)
            return
        }
        pendingDevice = device
        val permission = PendingIntent.getBroadcast(this, generation.toInt(), Intent(usbAction).setPackage(packageName)
            .setData(android.net.Uri.parse("scrcpyconnect://usb-permission/$generation")).putExtra("generation", generation),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.requestPermission(device, permission)
    }

    private fun openUsb(device: UsbDevice, result: MethodChannel.Result) {
        val manager = getSystemService(USB_SERVICE) as UsbManager
        val connection = manager.openDevice(device)
        if (connection == null) { result.error("usb_open_failed", "系统未能打开 USB 设备。", null); return }
        val leaseId = UUID.randomUUID().toString()
        UsbLeases.connections[leaseId] = connection
        result.success(mapOf("fd" to connection.fileDescriptor, "usbLeaseId" to leaseId, "usbDeviceId" to device.deviceName,
            "deviceName" to (device.productName ?: "Android 手机")))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!documents.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        documents.onDestroy()
        usbGeneration++
        usbChooser?.dismiss()
        usbChooser = null
        pendingUsb?.error("cancelled", "授权页面已关闭。", null)
        pendingUsb = null
        pendingDevice = null
        pendingUsbAttempt = null
        UsbLeases.connections.values.forEach { it.close() }
        UsbLeases.connections.clear()
        runCatching { unregisterReceiver(usbReceiver) }
        decoders.values.forEach { it.close() }
        decoders.clear()
        audio.detach(this)
        IncomingShares.releaseOwner(this)
        events = null
        DiscoveryNetwork.release("activity")
        super.onDestroy()
    }
}
