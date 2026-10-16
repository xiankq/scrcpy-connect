package dev.scrcpyconnect.scrcpy_connect

import android.content.Context
import android.net.wifi.WifiManager

/** Android filters inbound Wi-Fi multicast unless a live user of discovery
 * holds a lock. Activity and foreground service own independent leases. */
object DiscoveryNetwork {
    private val owners = mutableSetOf<String>()
    private var lock: WifiManager.MulticastLock? = null

    @Synchronized fun acquire(context: Context, owner: String) {
        if (owners.contains(owner)) return
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val active = lock ?: wifi.createMulticastLock("connect-discovery").apply {
            setReferenceCounted(false)
            lock = this
        }
        if (!active.isHeld) active.acquire()
        owners.add(owner)
    }

    @Synchronized fun release(owner: String) {
        owners.remove(owner)
        if (owners.isEmpty()) lock?.let { if (it.isHeld) it.release() }
    }
}
