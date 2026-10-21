package dev.scrcpyconnect.scrcpy_connect

/** Exercises the production application owner without Android framework stubs. */
object BackgroundKeepAliveTest {
    @JvmStatic fun main(args: Array<String>) {
        val writes = mutableListOf<String?>()
        val owner = BackgroundKeepAliveState(persistStop = writes::add)
        check(owner.request(true, automatic = true))
        check(owner.requested && !owner.running) // No page, audio or connection prerequisite.
        owner.started()
        check(owner.running)
        // Re-entry acknowledges the same application intent, not a new page lease.
        check(owner.request(true, automatic = true))
        check(owner.running && owner.requested)
        owner.stop("user")
        owner.destroyed()
        check(!owner.running && !owner.requested && writes.last() == "user")
        repeat(3) { check(!owner.request(true, automatic = true)) }
        check(!owner.requested)
        // A new process retains the explicit stop until an explicit request.
        val restored = BackgroundKeepAliveState(writes.last())
        check(!restored.request(true, automatic = true))
        check(restored.request(true, automatic = false))
        check(restored.stoppedReason == null && restored.requested)
        restored.started()
        check(!restored.destroyed()) // Unexpected system service termination.
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
        check(restored.destroyed()) // Quick explicit off/on requests a replacement.
        check(restored.requested && restored.stoppedReason == null)
        val pending = BackgroundKeepAliveState()
        pending.request(true, automatic = true)
        pending.request(false, automatic = false)
        pending.request(true, automatic = false)
        check(pending.stopping && !pending.running)
        check(pending.destroyed()) // Replacement also survives a not-yet-started service.
        println("PASS: application background entry, re-entry, explicit/system stop, persisted intent, platform refusal and rapid preference changes")
    }
}
