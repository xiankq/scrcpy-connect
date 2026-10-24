package dev.scrcpyconnect.scrcpy_connect

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** 应用拥有的设备连接前台服务，与媒体独立。 */
class ConnectionService : Service() {
    companion object {
        private const val STOP = "dev.scrcpyconnect.STOP_CONNECTIONS"
        private var lifetime: BackgroundKeepAliveState? = null
        val running get() = lifetime?.running == true
        val connectionRequested get() = lifetime?.requested == true
        val audioRequested get() = AudioPlaybackService.requested
        val mediaPlaybackReady get() = AudioPlaybackService.ready

        private fun state(context: Context): BackgroundKeepAliveState {
            lifetime?.let { return it }
            val preferences = context.getSharedPreferences("connection-background", Context.MODE_PRIVATE)
            var stopped = preferences.getString("stopped", null)
            // Android 任务管理器结束整个进程时没有回调；退出记录仅消费一次，使自动进入遵循此决定。
            if (Build.VERSION.SDK_INT >= 30) {
                val exit = runCatching {
                    (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
                        .getHistoricalProcessExitReasons(context.packageName, 0, 1).firstOrNull()
                }.getOrNull()
                if (exit != null && exit.timestamp > preferences.getLong("exit-seen", 0)) {
                    if (exit.reason == ApplicationExitInfo.REASON_USER_REQUESTED) stopped = "system"
                    preferences.edit().putLong("exit-seen", exit.timestamp).putString("stopped", stopped).apply()
                }
            }
            return BackgroundKeepAliveState(stopped) { reason ->
                preferences.edit().putString("stopped", reason).apply()
            }.also { lifetime = it }
        }

        fun keepConnections(context: Context, enabled: Boolean, automatic: Boolean = false) {
            val owner = state(context)
            if (!owner.request(enabled, automatic)) { changed(context); return }
            val intent = Intent(context, ConnectionService::class.java)
            try {
                if (!enabled) context.stopService(intent)
                else if (!owner.running && !owner.stopping) {
                    if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                } else if (owner.running) context.startService(intent)
            } catch (error: Exception) {
                owner.failed(error.message ?: "系统未允许启动设备活动后台。")
                changed(context)
                throw error
            }
            changed(context)
        }

        /** 保留的引擎可能经由新 Activity 再次进入，不能覆盖明确停止。 */
        fun appEntered(context: Context) {
            val owner = lifetime ?: return // 冷启动时等待 Dart 权威偏好。
            if (owner.enabled && !owner.running) {
                runCatching { keepConnections(context, true, automatic = true) }
            } else refreshNotification(context)
        }

        /** 权限或设置变化后重新发布提醒，不另取生命周期。 */
        fun refreshNotification(context: Context) {
            if (running && connectionRequested) {
                runCatching { context.startService(Intent(context, ConnectionService::class.java)) }
            }
        }

        fun keepAudio(context: Context, enabled: Boolean) = AudioPlaybackService.keep(context, enabled)

        fun status(context: Context): Map<String, Any> {
            val owner = state(context)
            val allowed = Build.VERSION.SDK_INT < 33 ||
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val title = when {
                owner.running -> "设备活动正在保持"
                owner.stoppedReason != null -> "设备活动后台已停止"
                owner.failure != null -> "后台保持受系统限制"
                owner.requested -> "正在启动设备活动后台"
                else -> "后台保持尚未启动"
            }
            val reason = when {
                owner.stoppedReason == "user" -> "已从通知停止设备活动；需明确重新启用，不会自动恢复连接或声音。"
                owner.stoppedReason == "system" -> "系统已停止设备活动后台；需明确重新启用，不会重放已结束的画面或声音。"
                owner.failure != null -> owner.failure!!
                !allowed -> "尚未允许显示连接通知。系统任务管理器仍可停止活动；允许通知后，可从通知栏返回或停止连接。"
                owner.running -> "已启动设备连接前台服务。后台活动仍受系统电量与网络策略影响。"
                owner.requested -> "正在等待系统确认设备连接前台服务。"
                else -> "后台保持已关闭；设备连接和画面仍遵循各自的生命周期。"
            }
            return mapOf("supported" to true, "running" to owner.running,
                "connectionRequested" to owner.requested, "audioRequested" to audioRequested,
                "mediaPlaybackReady" to mediaPlaybackReady, "notificationPermission" to allowed,
                "canRequest" to (!allowed || !owner.running), "stopped" to (owner.stoppedReason != null),
                "title" to title, "reason" to reason)
        }

        private fun changed(context: Context) {
            ProcessFlutterHost.emit(mapOf("type" to "background.changed", "data" to status(context)))
        }
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("connections", "设备连接与活动", NotificationManager.IMPORTANCE_LOW))
    }

    private fun updateForeground() {
        // 实际发现多播租约使用 CHANGE_WIFI_MULTICAST_STATE，它也是 connectedDevice 前台服务类型的前置条件。
        DiscoveryNetwork.acquire(this, "background")
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, ConnectionService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "connections") else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.ic_connection)
            .setContentTitle("邻接正在保持设备活动").setContentText("保持设备连接、发现与进行中的活动。")
            .setContentIntent(open).setOngoing(true).addAction(Notification.Action.Builder(null, "停止设备活动", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(2101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        else startForeground(2101, notification)
        state(this).started()
        changed(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            state(this).stop("user")
            ProcessFlutterHost.stopRequested(applicationContext)
            stopSelf()
        } else if (connectionRequested && !state(this).stopping) {
            try { updateForeground() } catch (error: Exception) {
                state(this).failed(error.message ?: "系统未允许保持设备连接。")
                changed(this)
                stopSelf()
            }
        } else stopSelf()
        // 用户或系统停止后不能立即触发粘性重启。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        val replacement = state(this).destroyed()
        DiscoveryNetwork.release("background")
        changed(this)
        super.onDestroy()
        if (replacement) runCatching { keepConnections(applicationContext, true, automatic = true) }
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
