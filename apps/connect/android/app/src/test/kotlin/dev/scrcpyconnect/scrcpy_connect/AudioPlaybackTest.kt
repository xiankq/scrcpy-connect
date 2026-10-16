package dev.scrcpyconnect.scrcpy_connect

/** JVM tests of production orchestration against hardware ports, not Android framework mocks. */
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
    private class Output : PcmSink {
        val calls = mutableListOf<String>()
        override var playState = PcmPlayState.STOPPED
        override val nativePlayState get() = playState.ordinal
        override val playbackHead get() = 0L
        var writes = 0
        var returnCount: Int? = null
        var failOn: String? = null
        private fun record(operation: String) {
            calls.add(operation)
            if (failOn == operation) throw IllegalStateException("hardware $operation failed")
        }
        override fun play() { record("play"); playState = PcmPlayState.PLAYING }
        override fun pause() { record("pause"); playState = PcmPlayState.PAUSED }
        override fun flush() { record("flush") }
        override fun release() { calls.add("release"); playState = PcmPlayState.STOPPED }
        override fun volume(value: Float) = true
        override fun write(data: ByteArray, offset: Int, count: Int): Int {
            check(playState == PcmPlayState.PLAYING)
            writes++
            return returnCount ?: count
        }
    }
    private val pcm = ByteArray(8192)

    @JvmStatic fun main(args: Array<String>) {
        sharedLeaseAndLateCallbacks()
        denialAndPermanentLossNeverRestart()
        manualPauseSurvivesFocusGainAndBackgroundChanges()
        pausedPcmAndStalePacketsAreDiscarded()
        closeAndWriteFailureCannotResurrectOutput()
        revisionsOrderEvenIneffectiveIntents()
        hardwareTransitionFailuresReleaseTheFocusLease()
        println("PASS: 7 audio contracts: shared focus, denial/permanent loss, compound pause, bounded PCM discard, close/late callbacks, receipt revisions, failed hardware transitions")
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
        check(events == 1) // One listener failure must not leave another source playing.
        check(first.state() == FocusSignal.PERMANENT_LOSS && second.state() == FocusSignal.PERMANENT_LOSS)
        driver.callbacks[1](FocusSignal.GRANTED)
        check(events == 1 && driver.requests == 2 && driver.abandons == 2)
        first.close(); second.close()
        check(driver.abandons == 2)
    }
    private fun manualPauseSurvivesFocusGainAndBackgroundChanges() {
        val playback = PcmPlayback()
        val output = Output()
        check(playback.attach(output))
        check(output.calls == listOf("pause", "flush")) // No focus, no play.
        playback.focus(FocusSignal.GRANTED)
        check(output.playState == PcmPlayState.PLAYING)
        playback.focus(FocusSignal.TRANSIENT_LOSS)
        check(output.calls.takeLast(2) == listOf("pause", "flush"))
        playback.manualPause(true)
        playback.focus(FocusSignal.GRANTED)
        playback.backgroundPause(true)
        playback.backgroundPause(false)
        check(output.playState == PcmPlayState.PAUSED)
        check(playback.status()["manualPaused"] == true)
        playback.manualPause(false)
        check(output.playState == PcmPlayState.PLAYING)
        playback.backgroundPause(true)
        playback.focus(FocusSignal.TRANSIENT_LOSS)
        playback.backgroundPause(false)
        check(output.playState == PcmPlayState.PAUSED)
        playback.focus(FocusSignal.GRANTED)
        check(playback.status()["applied"] == true && output.playState == PcmPlayState.PLAYING)
        playback.close()
    }
    private fun pausedPcmAndStalePacketsAreDiscarded() {
        val playback = PcmPlayback()
        val output = Output()
        playback.focus(FocusSignal.GRANTED)
        playback.attach(output)
        val oldEpoch = playback.generation()
        check(playback.consume(pcm, 0, pcm.size, oldEpoch) == 4096)
        check(playback.status()["bytesWritten"] == 4096L)
        playback.manualPause(true)
        val writes = output.writes
        repeat(1000) { check(playback.consume(pcm, 0, pcm.size, playback.generation()) == pcm.size) }
        check(output.writes == writes && playback.status()["bytesWritten"] == 4096L)
        check(playback.status()["droppedBytes"] == 1000L * pcm.size)
        val pausedEpoch = playback.generation()
        playback.manualPause(false)
        check(playback.consume(pcm, 0, pcm.size, oldEpoch) == pcm.size)
        check(playback.consume(pcm, 0, pcm.size, pausedEpoch) == pcm.size)
        check(output.writes == writes)
        output.returnCount = 0 // A nonblocking full hardware buffer, not a blocking lock holder.
        check(playback.consume(pcm, 0, pcm.size, playback.generation()) == 0)
        playback.manualPause(true)
        check(output.playState == PcmPlayState.PAUSED)
        playback.close()
    }
    private fun closeAndWriteFailureCannotResurrectOutput() {
        val playback = PcmPlayback()
        val output = Output()
        playback.focus(FocusSignal.GRANTED)
        playback.attach(output)
        output.returnCount = -6
        check(runCatching { playback.consume(pcm, 0, pcm.size, playback.generation()) }.isFailure)
        playback.close()
        val calls = output.calls.toList()
        playback.focus(FocusSignal.GRANTED)
        playback.manualPause(false)
        playback.backgroundPause(false)
        playback.close()
        check(output.calls == calls)
        check(playback.status()["closed"] == true && playback.status()["applied"] == false)
        check(playback.status()["playState"] == "stopped")
        val late = Output()
        check(!playback.attach(late))
        check(late.calls == listOf("release"))
        check(runCatching { playback.volume(Float.NaN, false) }.isFailure)
    }
    private fun revisionsOrderEvenIneffectiveIntents() {
        val playback = PcmPlayback()
        check(playback.status()["revision"] == 0L)
        check(playback.backgroundPause(true)["revision"] == 1L)
        check(playback.backgroundPause(true)["revision"] == 2L)
        check(playback.focus(FocusSignal.GRANTED)["revision"] == 3L)
        playback.attach(Output())
        check(playback.status()["revision"] == 4L)
        check(playback.manualPause(true)["revision"] == 5L)
        check(playback.focus(FocusSignal.GRANTED)["revision"] == 6L)
        check(playback.status()["playState"] == "paused")
        playback.close()
        check(playback.status()["revision"] == 7L)
        check(playback.status()["revision"] == 7L) // Read-only status never creates a new receipt.
    }

    private fun hardwareTransitionFailuresReleaseTheFocusLease() {
        for (operation in listOf("pause", "flush", "play")) {
            val driver = Driver()
            val leases = FocusLeases(driver)
            lateinit var playback: PcmPlayback
            val lease = checkNotNull(leases.acquire { playback.focus(it) })
            var failures = 0
            playback = PcmPlayback { error ->
                check(error.message == "hardware $operation failed")
                failures++
                lease.close()
            }
            val output = Output()
            playback.focus(FocusSignal.GRANTED)
            playback.attach(output)
            if (operation == "play") playback.manualPause(true)
            output.failOn = operation
            val error = runCatching {
                if (operation == "play") playback.manualPause(false)
                else playback.backgroundPause(true)
            }.exceptionOrNull()
            check(error?.message == "hardware $operation failed")
            check(failures == 1 && driver.abandons == 1)
            check(playback.status()["closed"] == true && playback.status()["applied"] == false)
            check(playback.status()["playState"] == "stopped")
            check(output.calls.count { it == "release" } == 1)
            val calls = output.calls.toList()
            driver.callbacks[0](FocusSignal.GRANTED)
            playback.manualPause(false)
            playback.backgroundPause(false)
            check(output.calls == calls && driver.requests == 1)
        }
    }

}
