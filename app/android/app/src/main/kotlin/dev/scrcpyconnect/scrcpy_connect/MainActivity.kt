package dev.scrcpyconnect.scrcpy_connect

import android.app.AlertDialog
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal object UsbLeases {
    // 缺少确认不能导致系统描述符无限保留；已提供的描述符不能超时释放，Rust 可能尚未执行 F_DUPFD_CLOEXEC。
    val connections = UsbHandoffLeases<UsbDeviceConnection>(16) { it.close() }
}

class MainActivity : FlutterActivity() {
    companion object {
        private var current: java.lang.ref.WeakReference<MainActivity>? = null
        fun cancelPendingConnections() { current?.get()?.cancelPendingConnectionsAndMedia() }
        fun sealUsbForRestart() {
            // 封存必须先于旧回调通知；即使旧 Dart 的回复端已消失，原始 FD 仍归进程登记。
            UsbLeases.connections.seal()
            runCatching { current?.get()?.cancelPendingConnectionsAndMedia() }
        }
        fun cancelUsbPermission(attempt: String?, candidate: String?): Map<String, Any?> {
            val lease = UsbLeases.connections.validateToken(candidate)
            // 没有 Activity 或匹配 UI 时也可确认撤销；这不确认任何 SDK 或 FD 的关闭。
            current?.get()?.usbRequests?.cancel(lease, attempt)
            return mapOf("cancelled" to true, "ownerLeaseId" to lease)
        }
        fun beginUsbRecovery(expected: String?, candidate: String?): Map<String, Any?> {
            val response = UsbLeases.connections.beginRecovery(expected, candidate)
            // 已完成候选的重复 begin 不得撤销其后新建的授权请求。
            if (response["ownerReady"] != true) runCatching { current?.get()?.cancelPendingConnectionsAndMedia() }
            return response
        }
    }
    private val documentsDelegate = lazy { PlatformDocuments.attach(this) }
    private val documents by documentsDelegate
    private val audio by lazy { NativeAudioRuntime.get(applicationContext) }
    private var pendingUsb: MethodChannel.Result? = null
    private var pendingDevice: UsbDevice? = null
    private val usbRequests = UsbPermissionRequests()
    private var usbChooser: AlertDialog? = null
    private var usbGeneration = 0L
    private val activityLease = Any()
    private val usbPermissionOwner = UUID.randomUUID().toString()
    private val usbAction get() = "$packageName.USB_PERMISSION"
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != usbAction || intent.getStringExtra("owner") != usbPermissionOwner ||
                intent.getLongExtra("generation", -1) != usbGeneration) return
            val lease = usbRequests.owner() ?: return
            val generation = usbGeneration
            if (intent.getStringExtra("ownerLeaseId") != lease || !usbRequestCurrent(generation, lease)) return
            val result = pendingUsb ?: return
            val device = pendingDevice
            clearPendingUsb()
            if (device == null || !(getSystemService(USB_SERVICE) as UsbManager).hasPermission(device)) {
                result.error("permission_denied", "尚未允许主控应用访问 USB 设备。", null)
            } else openUsb(device, result, generation, lease)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val previous = current?.get()
        current = java.lang.ref.WeakReference(this)
        if (previous !== this) {
            // 新页面只撤旧页面的授权 UI，不封存或关闭已交付的进程资源。
            runCatching { previous?.cancelPendingConnectionsAndMedia() }
            if (previous != null) runCatching { UsbLeases.connections.abandon(previous.activityLease) }
        }
        ProcessFlutterHost.attach(this)
        IncomingShares.attach(this)
        // 权限 PendingIntent 携带 URI 来区分尝试；只按 action 筛选会拒绝全部结果，使授权与拒绝都悬而未决。
        val usbFilter = IntentFilter(usbAction).apply { addDataScheme("scrcpyconnect") }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(usbReceiver, usbFilter, RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(usbReceiver, usbFilter)
        acceptIncoming(intent, false)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        ProcessFlutterHost.engine(context, flutterShellArgs.toArray())
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        ProcessFlutterHost.refreshEnvironment(this)
        audio.visible(this, true)
        DiscoveryNetwork.acquire(this, activityLease)
        ConnectionService.appEntered(this)
        AudioPlaybackService.refreshNotification(this)
    }

    override fun onStop() {
        audio.visible(this, false)
        DiscoveryNetwork.release(activityLease)
        super.onStop()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        ProcessFlutterHost.refreshEnvironment(this)
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean) {
        super.onMultiWindowModeChanged(isInMultiWindowMode)
        ProcessFlutterHost.refreshEnvironment(this)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        ProcessFlutterHost.refreshEnvironment(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptIncoming(intent, true)
    }

    internal fun readWindowEnvironment(): Map<String, Any> {
        val bounds = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.bounds
        } else {
            @Suppress("DEPRECATION")
            android.graphics.Rect(0, 0, window.decorView.width, window.decorView.height)
        }
        val density = resources.displayMetrics.density
        return mapOf(
            "width" to bounds.width() / density,
            "height" to bounds.height() / density,
            "windowId" to componentName.flattenToShortString(),
            "mode" to when {
                isInPictureInPictureMode -> "floating"
                isInMultiWindowMode -> "split"
                else -> "fullScreen"
            },
        )
    }

    private fun emit(event: Map<String, Any?>) = ProcessFlutterHost.emit(event)

    private fun acceptIncoming(intent: Intent?, renewed: Boolean) {
        val caller = if (Build.VERSION.SDK_INT >= 35) runCatching { if (renewed) currentCaller else initialCaller }.getOrNull() else null
        IncomingShares.accept(applicationContext, intent) { uri ->
            Build.VERSION.SDK_INT < 35 || runCatching {
                caller?.checkContentUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            }.getOrDefault(false)
        }
    }

    private fun clearPendingUsb() {
        pendingUsb = null
        pendingDevice = null
        usbRequests.clear()
    }

    private fun cancelPendingConnectionsAndMedia() {
        usbGeneration++
        val chooser = usbChooser
        val result = pendingUsb
        usbChooser = null
        clearPendingUsb()
        // 先撤销全部本地状态，再调用外部回调；失败不能恢复旧请求准入。
        runCatching { chooser?.dismiss() }
        runCatching { result?.error("cancelled", "USB 授权请求已撤销。", null) }
    }

    private fun usbRequestCurrent(generation: Long, lease: String): Boolean =
        current?.get() === this && generation == usbGeneration && UsbLeases.connections.accepts(lease)

    private fun usbFailure(result: MethodChannel.Result, error: Exception) {
        val failure = error as? UsbLeaseFailure
        result.error(failure?.code ?: "platform_error", error.message ?: "USB 系统操作未完成。", null)
    }

    internal fun handlePlatform(call: MethodCall, result: MethodChannel.Result) {
        try {
            val documentArguments = (call.arguments as? Map<*, *>)?.entries?.mapNotNull { entry ->
                (entry.key as? String)?.let { it to entry.value }
            }?.toMap().orEmpty()
            if (call.method.startsWith("documents.platform.")) {
                if (current?.get() !== this) {result.error("cancelled", "文档页面已替换。", null); return}
                if (documents.handle(this, call.method, documentArguments, result)) return
            }
            if (call.method.startsWith("sharing.platform.")) {
                if (current?.get() !== this) {result.error("cancelled", "分享页面已替换。", null); return}
                if (IncomingShares.handle(applicationContext, this, call, result)) return
            }
            if (call.method.startsWith("usb.") && current?.get() !== this) {
                throw UsbLeaseFailure("usb_owner_stale", "USB 授权页面已被替换。")
            }
            when (call.method) {
                "usb.authorize" -> authorizeUsb(call, result)
                "background.status" -> result.success(backgroundStatus())
                "background.request" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) {
                        if (call.argument<Boolean>("askNotificationPermission") == true && Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2102)
                        }
                    }
                    ConnectionService.keepConnections(this, enabled, automatic = call.argument<Boolean>("automatic") == true)
                    result.success(backgroundStatus() + mapOf("requested" to enabled))
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            if (call.method == "usb.authorize" && pendingUsb === result) {
                usbGeneration++
                val chooser = usbChooser
                usbChooser = null
                clearPendingUsb()
                runCatching { chooser?.dismiss() }
            }
            if (call.method.startsWith("usb.")) usbFailure(result, error)
            else result.error("platform_error", error.message ?: "系统操作未完成。", null)
        }
    }

    private fun backgroundStatus(): Map<String, Any> {
        return ConnectionService.status(this)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2102) {
            ConnectionService.refreshNotification(this)
            AudioPlaybackService.refreshNotification(this)
            emit(mapOf("type" to "background.changed", "data" to backgroundStatus()))
        }
    }

    private fun authorizeUsb(call: MethodCall, result: MethodChannel.Result) {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)) {
            result.error("usb_unsupported", "当前 Android 主控不支持 USB Host，请使用无线调试配对。", null)
            return
        }
        val lease = UsbLeases.connections.checkAdmission(call.argument<String>("ownerLeaseId"))
        UsbLeases.connections.checkCapacity(lease)
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
        usbRequests.begin(lease, call.argument<String>("attemptId"), ::cancelPendingConnectionsAndMedia)
        if (selected != null || devices.size == 1) requestUsbPermission(selected ?: devices.first(), generation, lease)
        else {
            usbChooser = AlertDialog.Builder(this).setTitle("选择被控手机")
                .setItems(devices.map { it.productName ?: it.deviceName }.toTypedArray()) { _, index ->
                    if (!usbRequestCurrent(generation, lease)) return@setItems
                    usbChooser = null
                    requestUsbPermission(devices[index], generation, lease)
                }
                .setOnCancelListener {
                    if (usbRequestCurrent(generation, lease)) cancelPendingConnectionsAndMedia()
                }.create()
            usbChooser?.show()
        }
    }

    private fun requestUsbPermission(device: UsbDevice, generation: Long, lease: String) {
        if (!usbRequestCurrent(generation, lease)) return
        val result = pendingUsb ?: return
        val manager = getSystemService(USB_SERVICE) as UsbManager
        if (manager.hasPermission(device)) {
            clearPendingUsb()
            openUsb(device, result, generation, lease)
            return
        }
        pendingDevice = device
        val permission = PendingIntent.getBroadcast(this, generation.toInt(), Intent(usbAction).setPackage(packageName)
            .setData(android.net.Uri.parse("scrcpyconnect://usb-permission/$usbPermissionOwner/$generation"))
            .putExtra("generation", generation).putExtra("owner", usbPermissionOwner).putExtra("ownerLeaseId", lease),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.requestPermission(device, permission)
    }

    private fun openUsb(device: UsbDevice, result: MethodChannel.Result, generation: Long, lease: String) {
        var delivered = false
        var registered = false
        try {
            if (!usbRequestCurrent(generation, lease)) throw UsbLeaseFailure("usb_owner_stale", "USB 授权请求已被替换。")
            UsbLeases.connections.checkCapacity(lease)
            val manager = getSystemService(USB_SERVICE) as UsbManager
            val leaseId = UUID.randomUUID().toString()
            val opened = UsbLeases.connections.open(leaseId, activityLease, lease) { manager.openDevice(device) }
            if (opened == null) { result.error("usb_open_failed", "系统未能打开 USB 设备。", null); return }
            registered = true
            val descriptor = opened.fileDescriptor
            if (descriptor < 0 || !usbRequestCurrent(generation, lease) ||
                !UsbLeases.connections.handoff(leaseId, activityLease, lease)) {
                throw UsbLeaseFailure("usb_owner_stale", "USB 描述符交付已失效。")
            }
            delivered = true
            // 回复可能已交付但确认丢失；交接后失败不能自行关闭 SDK 可能正在借用的原始 FD。
            val serial = try { device.serialNumber?.takeIf { it.isNotBlank() } } catch (_: SecurityException) { null }
            result.success(mapOf("fd" to descriptor, "usbLeaseId" to leaseId, "ownerLeaseId" to lease,
                "usbDeviceId" to device.deviceName, "serial" to serial, "deviceName" to (device.productName ?: "Android 手机")))
        } catch (error: Exception) {
            if (!delivered) {
                try {
                    if (registered) UsbLeases.connections.abandon(activityLease)
                } catch (cleanup: Exception) {
                    usbFailure(result, UsbLeaseFailure("usb_cleanup_unconfirmed", "USB 未交付资源尚未确认关闭。", cleanup))
                    return
                }
            }
            // 原回复端消失不影响进程登记；由下一次 SDK 排空后的接管精确回收。
            runCatching { usbFailure(result, error) }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!documentsDelegate.isInitialized() || !documents.onActivityResult(this, requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        if (documentsDelegate.isInitialized()) documents.onDestroy(this)
        cancelPendingConnectionsAndMedia()
        runCatching { UsbLeases.connections.abandon(activityLease) }
        runCatching { unregisterReceiver(usbReceiver) }
        audio.detach(this)
        IncomingShares.detach(this)
        ProcessFlutterHost.detach(this)
        DiscoveryNetwork.release(activityLease)
        super.onDestroy()
    }
}
