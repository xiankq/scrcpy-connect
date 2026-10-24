package dev.scrcpyconnect.scrcpy_connect

/** 无需 Android 框架桩即可验证生产应用所有者。 */
object BackgroundKeepAliveTest {
    @JvmStatic fun main(args: Array<String>) {
        val writes = mutableListOf<String?>()
        val owner = BackgroundKeepAliveState(persistStop = writes::add)
        check(owner.request(true, automatic = true))
        check(owner.requested && !owner.running) // 不要求页面、音频或连接前置条件。
        owner.started()
        check(owner.running)
        // 再次进入确认同一应用意图，不新增页面租约。
        check(owner.request(true, automatic = true))
        check(owner.running && owner.requested)
        owner.stop("user")
        owner.destroyed()
        check(!owner.running && !owner.requested && writes.last() == "user")
        repeat(3) { check(!owner.request(true, automatic = true)) }
        check(!owner.requested)
        // 新进程保留明确停止，直到收到明确请求。
        val restored = BackgroundKeepAliveState(writes.last())
        check(!restored.request(true, automatic = true))
        // 冷启动应用关闭偏好不能抹掉系统／用户停止标记，也不能解禁前台自动重连。
        val stoppedWrites = mutableListOf<String?>()
        val disabledAtStartup = BackgroundKeepAliveState("system", stoppedWrites::add)
        check(disabledAtStartup.request(false, automatic = true))
        check(disabledAtStartup.stoppedReason == "system" && stoppedWrites.isEmpty())
        check(!disabledAtStartup.request(true, automatic = true))
        check(disabledAtStartup.request(false, automatic = false))
        check(disabledAtStartup.stoppedReason == null && stoppedWrites == listOf<String?>(null))
        check(restored.request(true, automatic = false))
        check(restored.stoppedReason == null && restored.requested)
        restored.started()
        check(!restored.destroyed()) // 系统服务意外结束。
        check(restored.stoppedReason == "system" && !restored.requested)
        check(!restored.request(true, automatic = true))
        check(restored.request(false, automatic = false))
        check(!restored.requested && !restored.running)
        check(restored.request(true, automatic = false))
        restored.failed("foreground denied")
        check(!restored.running && restored.failure == "foreground denied")
        check(restored.request(true, automatic = false))
        restored.started()
        restored.request(false, automatic = false)
        restored.request(true, automatic = false)
        check(restored.destroyed()) // 快速明确关闭再开启会请求替换实例。
        check(restored.requested && restored.stoppedReason == null)
        val pending = BackgroundKeepAliveState()
        pending.request(true, automatic = true)
        pending.request(false, automatic = false)
        pending.request(true, automatic = false)
        check(pending.stopping && !pending.running)
        check(pending.destroyed()) // 服务尚未启动时替换意图也须保留。
        println("PASS: application background entry, re-entry, explicit/system stop, persisted intent, platform refusal and rapid preference changes")
    }
}
