package dev.scrcpyconnect.scrcpy_connect

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

class ConnectionService : Service() {
    companion object {
        @Volatile var running = false
            private set
        @Volatile var connectionRequested = false
            private set
        @Volatile var audioRequested = false
            private set
        @Volatile var mediaPlaybackReady = false
            private set

        fun keepConnections(context: Context, enabled: Boolean) {
            connectionRequested = enabled
            refresh(context)
        }
        fun keepAudio(context: Context, enabled: Boolean) {
            if (audioRequested == enabled && (!enabled || running)) return
            audioRequested = enabled
            refresh(context)
        }
        private fun refresh(context: Context) {
            val intent = Intent(context, ConnectionService::class.java)
            if (!connectionRequested && !audioRequested) {
                context.stopService(intent)
            } else if (!running && Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else context.startService(intent)
        }
    }
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("connections", "设备连接与活动", NotificationManager.IMPORTANCE_LOW))
        DiscoveryNetwork.acquire(this, "background")
    }
    private fun updateForeground() {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, ConnectionService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "connections") else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder.setSmallIcon(dev.scrcpyconnect.scrcpy_connect.R.drawable.ic_connection)
            .setContentTitle("邻接正在保持设备活动").setContentText(if (audioRequested) "已启用设备声音后台保持，可返回应用调整或停止。" else "保持已连接的设备与进行中的传输。")
            .setContentIntent(open).setOngoing(true).addAction(Notification.Action.Builder(null, "停止连接", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 29) {
            val types = (if (connectionRequested) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0) or
                (if (audioRequested) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0)
            startForeground(2101, notification, types)
        }
        else startForeground(2101, notification)
        running = true
        mediaPlaybackReady = audioRequested
        NativeAudioRuntime.get(applicationContext).foregroundChanged()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            connectionRequested = false
            audioRequested = false
            ProcessFlutterHost.stopRequested(applicationContext)
            NativeCore.stopAll()
            stopSelf()
        } else if (connectionRequested || audioRequested) updateForeground()
        else stopSelf()
        // User/system Stop must not cause an immediate sticky restart.
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        running = false
        mediaPlaybackReady = false
        NativeAudioRuntime.get(applicationContext).foregroundChanged()
        DiscoveryNetwork.release("background")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}

object NativeCore {
    init { System.loadLibrary("interop_bridge") }
    external fun stopAll(): Boolean
}
