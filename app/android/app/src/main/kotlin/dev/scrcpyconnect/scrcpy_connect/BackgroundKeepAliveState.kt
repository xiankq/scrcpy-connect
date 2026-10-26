package dev.scrcpyconnect.scrcpy_connect

/** 应用连接生命周期；媒体和页面所有权不进入此状态。 */
internal class BackgroundKeepAliveState(
    stopped: String? = null,
    private val persistStop: (String?) -> Unit = {},
) {
    var enabled = false
        private set
    var requested = false
        private set
    var running = false
        private set
    var stopping = false
        private set
    var stoppedReason: String? = stopped
        private set
    var failure: String? = null
        private set

    /** 返回 false 表示明确停止后抑制了自动请求。 */
    fun request(value: Boolean, automatic: Boolean): Boolean {
        enabled = value
        if (value && automatic && stoppedReason != null) return false
        if (!automatic) {
            stoppedReason = null
            persistStop(null)
        }
        if (!value && (requested || running)) stopping = true
        requested = value
        failure = null
        return true
    }

    fun started() { running = true; stopping = false; failure = null }

    fun failed(reason: String) {
        running = false
        stopping = false
        requested = false
        failure = reason
    }

    fun stop(reason: String) {
        requested = false
        stoppedReason = reason
        persistStop(reason)
    }

    fun destroyed(onSystemStop: () -> Unit = {}): Boolean {
        // 快速关闭再开启可能先于 Android 分发旧服务销毁；仅已确认且明确请求的替换可以重启。
        val replacement = stopping && requested && stoppedReason == null
        running = false
        stopping = false
        if (requested && !replacement) {
            stop("system")
            onSystemStop()
        }
        return replacement
    }
}
