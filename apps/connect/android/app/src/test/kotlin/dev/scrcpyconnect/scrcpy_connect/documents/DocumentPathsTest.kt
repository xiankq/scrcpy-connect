package dev.scrcpyconnect.scrcpy_connect

import java.io.File

/** Standalone JVM contract test: no Android mock implementation or test dependency is needed. */
object DocumentPathsTest {
    @JvmStatic fun main(args: Array<String>) {
        for (name in listOf("", ".", "..", "../outside", "nested/file", "nested\\file", "nul\u0000name", "line\nname", "a".repeat(256))) {
            check(runCatching { DocumentPaths.name(name) }.isFailure) { "unsafe name accepted" }
        }
        for (name in listOf("中文 empty", "file.bin", ".hidden", "name with spaces")) check(DocumentPaths.name(name) == name)
        val root = File("/private/cache")
        check(DocumentPaths.inside(root, File("/private/cache/item")))
        check(!DocumentPaths.inside(root, File("/private/cache-other/item")))
        check(!DocumentPaths.inside(root, root))
        check(!DocumentPaths.inside(root, File("/private/files/host_identity.pem")))
        println("PASS: document path traversal, alias prefixes, root exposure, names and Unicode contract")
    }
}
