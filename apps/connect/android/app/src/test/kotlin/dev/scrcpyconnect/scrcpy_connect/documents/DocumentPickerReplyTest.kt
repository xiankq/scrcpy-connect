package dev.scrcpyconnect.scrcpy_connect

import io.flutter.plugin.common.MethodChannel

/** Standalone JVM ownership checks; no fake document provider or Android UI. */
object DocumentPickerReplyTest {
    private class Reply : MethodChannel.Result {
        val values = mutableListOf<Any?>()
        val errors = mutableListOf<String>()
        override fun success(value: Any?) {values.add(value)}
        override fun error(code: String, message: String?, details: Any?) {errors.add(code)}
        override fun notImplemented() {error("not_implemented", null, null)}
    }
    @JvmStatic fun main(args: Array<String>) {
        val cancelled = Reply()
        val pending = DocumentPickerReply(cancelled)
        pending.success(mapOf("status" to "cancelled"))
        // The Binder worker may finish successfully or throw after cancel.
        pending.success(mapOf("status" to "selected"))
        pending.error("late_provider", "late", null)
        check(cancelled.values == listOf(mapOf("status" to "cancelled")))
        check(cancelled.errors.isEmpty())
        val succeeded = Reply()
        val completed = DocumentPickerReply(succeeded)
        completed.success(mapOf("status" to "selected"))
        completed.success(mapOf("status" to "cancelled"))
        check(succeeded.values == listOf(mapOf("status" to "selected")))
        val rejected = Reply()
        val failed = DocumentPickerReply(rejected)
        failed.error("permission_denied", "denied", null)
        failed.success(mapOf("status" to "cancelled"))
        check(rejected.errors == listOf("permission_denied"))
        check(rejected.values.isEmpty())
        println("PASS: picker cancel, late completion, failure and exactly-once replies")
    }
}
