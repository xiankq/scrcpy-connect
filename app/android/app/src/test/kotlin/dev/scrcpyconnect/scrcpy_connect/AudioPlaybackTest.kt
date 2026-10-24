package dev.scrcpyconnect.scrcpy_connect

/** 在硬件端口上测试生产编排，不模拟 Android 框架。 */
object AudioPlaybackTest {
    private class Driver : FocusDriver {
        var requests = 0
        var abandons = 0
        var granted = true
        val callbacks = mutableListOf<(FocusSignal) -> Unit>()
        override fun request(changed: (FocusSignal) -> Unit): Boolean {
            requests++
            callbacks.add(changed)
            return granted
        }
        override fun abandon() { abandons++ }
    }
    @JvmStatic fun main(args: Array<String>) {
        sharedLeaseAndLateCallbacks()
        denialAndPermanentLossNeverRestart()
        println("PASS: OS shared focus, denial, permanent loss and stale callback isolation")
    }
    private fun sharedLeaseAndLateCallbacks() {
        val driver = Driver()
        val leases = FocusLeases(driver)
        val firstEvents = mutableListOf<FocusSignal>()
        val secondEvents = mutableListOf<FocusSignal>()
        val first = checkNotNull(leases.acquire { firstEvents.add(it) })
        val second = checkNotNull(leases.acquire { secondEvents.add(it) })
        check(driver.requests == 1)
        first.close()
        check(driver.abandons == 0)
        driver.callbacks[0](FocusSignal.TRANSIENT_LOSS)
        check(firstEvents.isEmpty())
        check(secondEvents == listOf(FocusSignal.TRANSIENT_LOSS))
        check(second.state() == FocusSignal.TRANSIENT_LOSS)
        second.close()
        second.close()
        check(driver.abandons == 1)
        val freshEvents = mutableListOf<FocusSignal>()
        val fresh = checkNotNull(leases.acquire { freshEvents.add(it) })
        check(driver.requests == 2)
        driver.callbacks[0](FocusSignal.PERMANENT_LOSS)
        driver.callbacks[0](FocusSignal.GRANTED)
        check(fresh.state() == FocusSignal.GRANTED && freshEvents.isEmpty())
        fresh.close()
        check(driver.abandons == 2)
    }
    private fun denialAndPermanentLossNeverRestart() {
        val driver = Driver()
        driver.granted = false
        val leases = FocusLeases(driver)
        var events = 0
        check(leases.acquire { events++ } == null)
        driver.callbacks[0](FocusSignal.GRANTED)
        check(events == 0 && driver.abandons == 1)
        driver.granted = true
        val first = checkNotNull(leases.acquire { throw IllegalStateException("one owner failed") })
        val second = checkNotNull(leases.acquire { events++ })
        driver.callbacks[1](FocusSignal.PERMANENT_LOSS)
        check(events == 1) // 一个监听器失败不能使其他音源继续播放。
        check(first.state() == FocusSignal.PERMANENT_LOSS && second.state() == FocusSignal.PERMANENT_LOSS)
        driver.callbacks[1](FocusSignal.GRANTED)
        check(events == 1 && driver.requests == 2 && driver.abandons == 2)
        first.close(); second.close()
        check(driver.abandons == 2)
    }
}
