package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.net.wifi.WifiManager

/** Android 会过滤入站 Wi-Fi 多播，发现活动必须持有锁；Activity 和前台服务独立拥有租约。 */
object DiscoveryNetwork {
    private val owners = DiscoveryLeaseOwners()
    private var lock: WifiManager.MulticastLock? = null

    @Synchronized fun acquire(context: Context, owner: Any) {
        owners.acquire(owner) {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifi == null) false else {
                val active = lock ?: wifi.createMulticastLock("connect-discovery").apply {
                    setReferenceCounted(false)
                    lock = this
                }
                if (!active.isHeld) active.acquire()
                true
            }
        }
    }

    @Synchronized fun release(owner: Any) {
        owners.release(owner) { lock?.let { if (it.isHeld) it.release() } }
    }
}
