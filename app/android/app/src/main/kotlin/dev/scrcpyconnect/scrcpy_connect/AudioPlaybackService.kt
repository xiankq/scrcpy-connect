package dev.scrcpyconnect.scrcpy_connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/** 仅在 Dart 音频输出所有者请求媒体播放期间存在。 */
class AudioPlaybackService : Service() {
    companion object {
        @Volatile var requested = false
            private set
        @Volatile var ready = false
            private set

        fun keep(context: Context, enabled: Boolean) {
            if (requested == enabled && ready == enabled) return
            requested = enabled
            val intent = Intent(context, AudioPlaybackService::class.java)
            try {
                if (!enabled) context.stopService(intent)
                else if (!ready && Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                requested = false
                throw error
            }
        }

        fun refreshNotification(context: Context) {
            if (requested && ready) {
                try {
                    context.startService(Intent(context, AudioPlaybackService::class.java))
                } catch (error: IllegalStateException) {
                    Log.w("Interconnect", "audio.refresh_notification: ${error.javaClass.simpleName}")
                } catch (error: SecurityException) {
                    Log.w("Interconnect", "audio.refresh_notification: ${error.javaClass.simpleName}")
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("device-audio", "设备声音", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!requested) { stopSelf(); return START_NOT_STICKY }
        try {
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "device-audio") else @Suppress("DEPRECATION") Notification.Builder(this)
            val notification = builder.setSmallIcon(R.drawable.ic_connection)
                .setContentTitle("邻接正在播放设备声音").setContentText("返回应用可调整或停止当前设备声音。")
                .setContentIntent(open).setOngoing(true).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(2103, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(2103, notification)
            ready = true
        } catch (error: Exception) {
            Log.w("Interconnect", "audio.start_foreground: ${error.javaClass.simpleName}")
            requested = false
            ready = false
            stopSelf()
        }
        NativeAudioRuntime.get(applicationContext).foregroundChanged()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        ready = false
        NativeAudioRuntime.get(applicationContext).foregroundChanged()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
