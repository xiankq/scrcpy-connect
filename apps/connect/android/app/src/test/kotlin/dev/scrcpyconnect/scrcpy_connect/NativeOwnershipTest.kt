package dev.scrcpyconnect.scrcpy_connect

// Shared import policy contracts now execute against the Rust ImportManager.
object NativeOwnershipTest {
    @JvmStatic fun main(args: Array<String>) {
        activityRebindingDoesNotReplaceAudio()
        println("PASS: Android audio Activity attachment ownership")
    }
    private class Audio : OwnedAudio {
        var closed = 0; var paused = false; var revision = 0L
        override fun background(paused: Boolean): Map<String, Any?> { this.paused = paused; revision++; return status() }
        override fun status() = mapOf("sourceId" to "same-source", "applied" to true, "revision" to revision, "playState" to if (paused) "paused" else "playing")
        override fun close() { closed++ }
    }
    private fun activityRebindingDoesNotReplaceAudio() {
        val receipts = mutableListOf<Map<String, Any?>>()
        val owner = AudioSessionOwnership { receipts.add(it) }
        val oldActivity = Any(); val newActivity = Any(); val audio = Audio()
        owner.setVisible(oldActivity, true); owner.add("same-source", audio)
        owner.setVisible(oldActivity, false); check(audio.paused && audio.closed == 0)
        owner.setVisible(newActivity, true); check(!audio.paused && owner.get("same-source") === audio)
        owner.backgroundAllowed = true
        owner.setVisible(newActivity, false); check(!audio.paused && audio.closed == 0)
        owner.setVisible(Any(), false); check(!audio.paused) // late detach cannot stop shared owner
        check(owner.snapshots().single()["sourceId"] == "same-source")
        owner.stopAll(); owner.stopAll(); check(audio.closed == 1 && owner.empty())
    }
}
