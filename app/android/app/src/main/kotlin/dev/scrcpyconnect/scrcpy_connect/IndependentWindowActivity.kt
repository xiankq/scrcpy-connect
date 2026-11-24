package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.Context
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.graphics.Rect
import android.net.Uri
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min

/** A second Flutter engine hosting one remote control session. */
class IndependentWindowActivity : FlutterActivity() {
    private var engine: FlutterEngine? = null
    private val windowId: String by lazy {
        intent.getStringExtra(EXTRA_WINDOW_ID).orEmpty()
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        ConnectApplication.engineGroup(context, flutterShellArgs.toArray()).createAndRunEngine(
            FlutterEngineGroup.Options(context.applicationContext)
                .setInitialRoute(intent.getStringExtra(EXTRA_ROUTE) ?: "/__independent_remote"),
        )

    override fun shouldDestroyEngineWithHost(): Boolean = true

    override fun onStart() {
        super.onStart()
        NativeAudioRuntime.get(applicationContext).visible(this, true)
    }

    override fun onStop() {
        NativeAudioRuntime.get(applicationContext).visible(this, false)
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engine = flutterEngine
        windows[windowId] = this
        @Suppress("DEPRECATION")
        setTaskDescription(ActivityManager.TaskDescription(intent.getStringExtra(EXTRA_TITLE)))
        ProcessFlutterHost.attachIndependent(this, flutterEngine)
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

    override fun onDestroy() {
        engine?.let { ProcessFlutterHost.detachIndependent(it) }
        engine = null
        super.onDestroy()
        if (windows[windowId] === this) {
            windows.remove(windowId)
            ProcessFlutterHost.remoteWindowDestroyed(windowId)
        }
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
            "mode" to when {
                isInPictureInPictureMode -> "floating"
                isInMultiWindowMode -> "split"
                else -> "fullScreen"
            },
        )
    }

    internal fun readWindowId(): String = windowId

    companion object {
        private const val EXTRA_WINDOW_ID = "scrcpy_connect.window_id"
        private const val EXTRA_ROUTE = "scrcpy_connect.window_route"
        private const val EXTRA_TITLE = "scrcpy_connect.window_title"
        private val windows = mutableMapOf<String, IndependentWindowActivity>()

        fun openFrom(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
            val id = call.argument<String>("windowId")
            val route = call.argument<String>("initialRoute")
            val title = call.argument<String>("title")
            if (id.isNullOrEmpty() || route.isNullOrEmpty() || title.isNullOrEmpty()) {
                result.error("invalid_window_request", "独立窗口参数不完整。", null)
                return
            }
            val intent = Intent(activity, IndependentWindowActivity::class.java)
                .setData(Uri.Builder().scheme("scrcpyconnect").authority("remote-window").appendPath(id).build())
                .putExtra(EXTRA_WINDOW_ID, id)
                .putExtra(EXTRA_ROUTE, route)
                .putExtra(EXTRA_TITLE, title)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            val options = ActivityOptions.makeBasic()
            if (windows[id] == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                activity.packageManager.hasSystemFeature(PackageManager.FEATURE_FREEFORM_WINDOW_MANAGEMENT)
            ) {
                val area = activity.windowManager.maximumWindowMetrics.bounds
                val ratio = call.argument<Double>("aspectRatio") ?: (460.0 / 780.0)
                val navigationHeight = call.argument<Double>("navigationHeight") ?: 0.0
                val navigation = (navigationHeight * activity.resources.displayMetrics.density).toInt()
                val width = min(area.width() * 0.72, (area.height() * 0.80 - navigation) * ratio).toInt()
                val height = (width / ratio).toInt() + navigation
                val left = area.centerX() - width / 2
                val top = area.centerY() - height / 2
                options.setLaunchBounds(Rect(left, top, left + width, top + height))
            }
            try {
                activity.startActivity(intent, options.toBundle())
                result.success(mapOf("supported" to true, "windowId" to id))
            } catch (error: ActivityNotFoundException) {
                result.success(mapOf("supported" to false, "reason" to "系统未能打开独立控制页面。"))
            }
        }

        fun close(id: String?) {
            windows[id]?.finishAndRemoveTask()
        }

        fun showWorkbench(context: Context) {
            context.startActivity(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
