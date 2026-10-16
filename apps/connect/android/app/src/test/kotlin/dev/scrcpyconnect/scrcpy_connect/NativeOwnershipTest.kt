package dev.scrcpyconnect.scrcpy_connect

/** Tests production thin OS ownership without constructing framework stubs. */
object NativeOwnershipTest {
    @JvmStatic fun main(args: Array<String>) {
        val owner = AudioPlatformOwnership()
        val firstActivity = Any()
        val replacementActivity = Any()
        check(owner.visible(firstActivity, true))
        check(!owner.visible(replacementActivity, true))
        check(!owner.visible(firstActivity, false) && owner.visible)
        check(owner.claim("first-engine"))
        val first = owner.nextEpoch()
        check(!owner.claim("other-engine"))
        check(owner.visible(replacementActivity, false) && !owner.visible)
        check(owner.epoch == first) // Activity loss does not release the OS lease.
        check(!owner.clearEpoch(first + 1) && owner.epoch == first)
        owner.background = true
        check(owner.clearEpoch(first))
        owner.releaseIfUnused()
        check(owner.owner == "first-engine") // Actual FGS request still owned.
        owner.background = false
        owner.releaseIfUnused()
        check(owner.claim("new-engine"))
        val next = owner.nextEpoch()
        check(next > first)
        check(!owner.clearEpoch(first) && owner.epoch == next)
        check(!owner.claim("first-engine")) // Late old owner cannot claim new lease.
        check(owner.clearEpoch(next))
        owner.releaseIfUnused()
        check(owner.owner == null)
        println("PASS: Activity visibility aggregation, owner refusal, background ownership and stale epoch isolation")
    }
}
