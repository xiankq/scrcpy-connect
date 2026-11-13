package dev.scrcpyconnect.scrcpy_connect

import android.app.Activity
import android.graphics.Rect
import androidx.core.content.ContextCompat
import androidx.core.util.Consumer
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
    private var latest = snapshot(emptyList())
    private val listener = Consumer<WindowLayoutInfo> { info ->
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

    fun close() {
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
        return mapOf(
            "width" to bounds.width() / density,
            "height" to bounds.height() / density,
            "windowId" to windowId(),
            "posture" to posture,
            "displayFeatures" to folding.map { feature -> featurePayload(feature, density) },
        )
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
        )
    }
}
