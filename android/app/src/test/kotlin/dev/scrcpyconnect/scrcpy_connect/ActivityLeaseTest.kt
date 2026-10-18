package dev.scrcpyconnect.scrcpy_connect

/** Drives production ownership code through observable OS acquire/close ports. */
object ActivityLeaseTest {
    private class Descriptor {
        var closes = 0
        fun readBeforeRustDup() { check(closes == 0) }
        fun close() { closes++; check(closes == 1) }
    }
    @JvmStatic fun main(args: Array<String>) {
        discoveryOverlap()
        usbHandoffOverlap()
        boundedUnacknowledgedHandoffs()
        println("PASS: overlapping Activity discovery, USB handoff/ACK ownership and bounded missing ACKs")
    }
    private fun discoveryOverlap() {
        val ownership = DiscoveryLeaseOwners()
        val a = Any(); val b = Any(); val service = "background"
        var physicalAcquires = 0; var physicalReleases = 0
        fun start(owner: Any) = ownership.acquire(owner) { physicalAcquires++; true }
        fun stop(owner: Any) = ownership.release(owner) { physicalReleases++ }
        check(start(a)); check(start(a)); check(start(b))
        stop(a) // A.onStop after B.onStart must preserve B's physical lock.
        stop(a) // A.onDestroy is a duplicate release, not B's release.
        check(physicalAcquires == 1 && physicalReleases == 0)
        check(start(service)); stop(b)
        check(physicalReleases == 0)
        stop(service); stop(b)
        check(physicalReleases == 1)
        check(!ownership.acquire(a) { false })
        stop(a) // Failed OS acquire never creates a releasable owner.
        check(physicalReleases == 1)
        check(start(b)); stop(b)
        check(physicalAcquires == 2 && physicalReleases == 2)
    }
    private fun usbHandoffOverlap() {
        val ownership = UsbHandoffLeases<Descriptor>(4) { it.close() }
        val a = Any(); val b = Any()
        val aPending = Descriptor(); val aOffered = Descriptor(); val bPending = Descriptor()
        check(ownership.register("a-pending", a, aPending))
        check(ownership.register("a-offered", a, aOffered))
        check(!ownership.handoff("a-offered", b)) // Another Activity cannot take a pending request.
        check(ownership.handoff("a-offered", a))
        check(ownership.register("b-pending", b, bPending))
        ownership.abandon(a)
        check(aPending.closes == 1)
        aOffered.readBeforeRustDup() // A.onDestroy cannot invalidate the fd in flight to Rust.
        bPending.readBeforeRustDup()
        check(ownership.handoff("b-pending", b))
        ownership.abandon(a); ownership.abandon(b)
        aOffered.readBeforeRustDup(); bPending.readBeforeRustDup()
        check(ownership.release("a-offered")) // Rust duplicated/rejected A and sends its exact ACK.
        check(!ownership.release("a-offered"))
        check(!ownership.release("a-pending"))
        bPending.readBeforeRustDup() // A's late ACK cannot close B's accepted fd.
        check(ownership.release("b-pending"))
        check(aOffered.closes == 1 && bPending.closes == 1)
    }
    private fun boundedUnacknowledgedHandoffs() {
        val ownership = UsbHandoffLeases<Descriptor>(1) { it.close() }
        val a = Any(); val b = Any()
        val first = Descriptor(); val rejected = Descriptor()
        check(ownership.register("first", a, first))
        check(ownership.handoff("first", a))
        ownership.abandon(a)
        check(!ownership.register("second", b, rejected))
        rejected.close() // Caller retains ownership when admission fails.
        first.readBeforeRustDup()
        check(ownership.release("first"))
        val next = Descriptor()
        check(ownership.register("next", b, next))
        ownership.abandon(b)
        check(next.closes == 1 && first.closes == 1)
    }
}
