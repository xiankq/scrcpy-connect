package dev.scrcpyconnect.scrcpy_connect

/** Application connection lifetime. Media/page ownership never enters this state. */
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

    /** False means an automatic request was suppressed after an explicit stop. */
    fun request(value: Boolean, automatic: Boolean): Boolean {
        enabled = value
        if (value && automatic && stoppedReason != null) return false
        if (!automatic || !value) {
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

    fun destroyed(): Boolean {
        // A rapid off/on can arrive before Android dispatches the old destroy.
        // Only this acknowledged, explicitly requested replacement may restart.
        val replacement = stopping && requested && stoppedReason == null
        running = false
        stopping = false
        if (requested && !replacement) stop("system")
        return replacement
    }
}
