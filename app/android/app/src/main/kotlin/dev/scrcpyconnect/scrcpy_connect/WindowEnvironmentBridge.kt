package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.graphics.Rect
import androidx.core.content.ContextCompat
import androidx.core.util.Consumer
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter
import androidx.window.layout.DisplayFeature
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.BinaryMessenger

/**
 * Projects AndroidX WindowManager facts into the platform-neutral Dart payload.
 * The adapter owns only window geometry and posture; control session state stays
 * in Dart and in the engine that owns the Activity.
 */
internal class WindowEnvironmentBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val windowId: () -> String,
) : EventChannel.StreamHandler {
    private val channel = EventChannel(
        messenger,
        "dev.scrcpyconnect/window_environment/events",
    )
    private val tracker = WindowInfoTrackerCallbackAdapter(
        WindowInfoTracker.getOrCreate(activity),
    )
    private val executor = ContextCompat.getMainExecutor(activity)
    private var sink: EventChannel.EventSink? = null
    private var closed = false
    private var latestFeatures: List<DisplayFeature> = emptyList()
    private var latest = snapshot(emptyList())
    private val listener = Consumer<WindowLayoutInfo> { info ->
        latestFeatures = info.displayFeatures
        latest = snapshot(info.displayFeatures)
        sink?.success(latest)
    }

    init {
        channel.setStreamHandler(this)
        tracker.addWindowLayoutInfoListener(activity, executor, listener)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        events.success(latest)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun readEnvironment(): Map<String, Any> = latest

    /** Re-emits mode, bounds and cutouts after an Activity callback. */
    fun refresh() {
        latest = snapshot(latestFeatures)
        sink?.success(latest)
    }

    fun isFor(owner: Activity): Boolean = activity === owner

    fun close() {
        if (closed) return
        closed = true
        tracker.removeWindowLayoutInfoListener(listener)
        sink = null
        channel.setStreamHandler(null)
    }

    private fun snapshot(features: List<DisplayFeature>): Map<String, Any> {
        val density = activity.resources.displayMetrics.density
        val bounds = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            activity.windowManager.currentWindowMetrics.bounds
        } else {
            @Suppress("DEPRECATION")
            Rect(0, 0, activity.window.decorView.width, activity.window.decorView.height)
        }
        val folding = features.filterIsInstance<FoldingFeature>()
        val posture = folding.firstOrNull()?.let { feature ->
            when {
                feature.state == FoldingFeature.State.HALF_OPENED &&
                    feature.orientation == FoldingFeature.Orientation.HORIZONTAL -> "tabletop"
                feature.state == FoldingFeature.State.HALF_OPENED -> "book"
                feature.state == FoldingFeature.State.FLAT -> "flat"
                else -> "normal"
            }
        } ?: "normal"
        val projectedFeatures = folding.map { feature ->
            featurePayload(feature, density)
        }.toMutableList()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            val cutouts = activity.window.decorView.rootWindowInsets
                ?.displayCutout
                ?.boundingRects
                .orEmpty()
            projectedFeatures += cutouts.map { rect -> cutoutPayload(rect, density) }
        }
        return mapOf(
            "width" to bounds.width() / density,
            "height" to bounds.height() / density,
            "windowId" to windowId(),
            "mode" to windowMode(),
            "posture" to posture,
            "insets" to insetsPayload(),
            "displayFeatures" to projectedFeatures,
        )
    }

    private fun insetsPayload(): Map<String, Any> {
        val insets = ViewCompat.getRootWindowInsets(activity.window.decorView)
            ?.getInsetsIgnoringVisibility(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout(),
            )
        return mapOf(
            "left" to (insets?.left ?: 0) / activity.resources.displayMetrics.density,
            "top" to (insets?.top ?: 0) / activity.resources.displayMetrics.density,
            "right" to (insets?.right ?: 0) / activity.resources.displayMetrics.density,
            "bottom" to (insets?.bottom ?: 0) / activity.resources.displayMetrics.density,
        )
    }

    private fun windowMode(): String = when {
        activity.isInPictureInPictureMode -> "floating"
        activity.isInMultiWindowMode -> "split"
        else -> "fullScreen"
    }

    private fun featurePayload(
        feature: FoldingFeature,
        density: Float,
    ): Map<String, Any> {
        val bounds = feature.bounds
        val type = if (feature.occlusionType == FoldingFeature.OcclusionType.FULL) {
            "hinge"
        } else {
            "fold"
        }
        val state = when {
            feature.state == FoldingFeature.State.HALF_OPENED &&
                feature.orientation == FoldingFeature.Orientation.HORIZONTAL -> "tabletop"
            feature.state == FoldingFeature.State.HALF_OPENED -> "book"
            feature.state == FoldingFeature.State.FLAT -> "flat"
            else -> "normal"
        }
        return mapOf(
            "left" to bounds.left / density,
            "top" to bounds.top / density,
            "width" to bounds.width() / density,
            "height" to bounds.height() / density,
            "type" to type,
            "state" to state,
            "separating" to feature.isSeparating,
        )
    }

    private fun cutoutPayload(rect: Rect, density: Float): Map<String, Any> = mapOf(
        "left" to rect.left / density,
        "top" to rect.top / density,
        "width" to rect.width() / density,
        "height" to rect.height() / density,
        "type" to "cutout",
    )
}
