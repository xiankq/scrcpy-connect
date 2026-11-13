package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** A second Flutter engine hosting one remote control session. */
class IndependentWindowActivity : FlutterActivity() {
    private var engine: FlutterEngine? = null
    private val windowId: String by lazy {
        intent.getStringExtra(EXTRA_WINDOW_ID) ?: UUID.randomUUID().toString()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engine = flutterEngine
        ProcessFlutterHost.attachIndependent(this, flutterEngine)
    }

    override fun onDestroy() {
        engine?.let { ProcessFlutterHost.detachIndependent(it) }
        engine = null
        super.onDestroy()
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
            "windowId" to windowId,
        )
    }

    internal fun readWindowId(): String = windowId

    internal fun openIndependent(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId")
        val packageName = call.argument<String>("packageName")
        val sessionId = call.argument<String>("sessionId")
        val route = call.argument<String>("initialRoute")
        if (deviceId.isNullOrEmpty() || packageName.isNullOrEmpty() ||
            sessionId.isNullOrEmpty() || route.isNullOrEmpty()) {
            result.error("invalid_window_request", "独立窗口参数不完整。", null)
            return
        }
        launch(this, deviceId, packageName, sessionId, route)
        result.success(mapOf("supported" to true, "windowId" to windowId))
    }

    companion object {
        private const val EXTRA_WINDOW_ID = "scrcpy_connect.window_id"

        fun openFrom(context: Context, call: MethodCall, result: MethodChannel.Result) {
            val deviceId = call.argument<String>("deviceId")
            val packageName = call.argument<String>("packageName")
            val sessionId = call.argument<String>("sessionId")
            val route = call.argument<String>("initialRoute")
            if (deviceId.isNullOrEmpty() || packageName.isNullOrEmpty() ||
                sessionId.isNullOrEmpty() || route.isNullOrEmpty()) {
                result.error("invalid_window_request", "独立窗口参数不完整。", null)
                return
            }
            val windowId = UUID.randomUUID().toString()
            launch(context, deviceId, packageName, sessionId, route, windowId)
            result.success(mapOf("supported" to true, "windowId" to windowId))
        }

        private fun launch(
            context: Context,
            deviceId: String,
            packageName: String,
            sessionId: String,
            route: String,
            windowId: String = UUID.randomUUID().toString(),
        ) {
            val intent = FlutterActivity.withNewEngineInGroup(ConnectApplication.ENGINE_GROUP_ID)
                .initialRoute(route)
                .build(context)
                .setClass(context, IndependentWindowActivity::class.java)
                .putExtra(EXTRA_WINDOW_ID, windowId)
                .putExtra("scrcpy_connect.device_id", deviceId)
                .putExtra("scrcpy_connect.package_name", packageName)
                .putExtra("scrcpy_connect.session_id", sessionId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            context.startActivity(intent)
        }
    }
}
