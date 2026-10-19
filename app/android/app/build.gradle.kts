import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { load(it) }
}

// Fail before Flutter AOT/Rust compilation instead of successfully publishing
// an unsigned app-release.apk which Android's installer cannot parse.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
        check(releaseKeyFile.isFile) {
            "Release signing is not configured. From the repository root run: " +
                "dart tool/android.dart init-signing (local sideload key), " +
                "or provide app/android/key.properties with your release key."
        }
    }
}

android {
    namespace = "dev.scrcpyconnect.scrcpy_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.scrcpyconnect.scrcpy_connect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter's default filters include all three supported ABIs even when
        // --target-platform selects one. Exclude plugin-only ABIs: an installer
        // must never select an architecture lacking Flutter and the Rust core.
        if (providers.gradleProperty("split-per-abi").orNull != "true") {
            val requestedPlatforms = providers.gradleProperty("target-platform")
                .orElse("android-arm,android-arm64,android-x64").get().split(",")
            val abis = mapOf(
                "android-arm" to "armeabi-v7a",
                "android-arm64" to "arm64-v8a",
                "android-x64" to "x86_64",
            )
            ndk {
                abiFilters.clear()
                abiFilters.addAll(requestedPlatforms.map {
                    requireNotNull(abis[it]) { "Unsupported Android target platform: $it" }
                })
            }
        }
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
                    require(!releaseKey.getProperty(name).isNullOrBlank()) { "key.properties missing $name" }
                }
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
