package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.net.wifi.WifiManager

/** Android filters inbound Wi-Fi multicast unless a live user of discovery
 * holds a lock. Activity and foreground service own independent leases. */
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
