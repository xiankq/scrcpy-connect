import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android 与 Kotlin Gradle 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { load(it) }
}

// 在 Flutter AOT 和 Rust 编译前就检查签名，避免成功发布 Android 安装器无法解析的未签名 app-release.apk。
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
        check(releaseKeyFile.isFile) {
            "Release signing is not configured. From the repository root run: " +
                "dart scripts/android.dart init-signing (local sideload key), " +
                "or provide app/android/key.properties with your release key."
        }
    }
}

android {
    namespace = "dev.scrcpyconnect.scrcpy_connect"
    // flutter_local_notifications 23 要求 Android 37。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.scrcpyconnect.scrcpy_connect"
        // 按应用需求调整以下配置；说明见 https://flutter.dev/to/review-gradle-config。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 版本号读取 pubspec.yaml。拆分 APK 时 Flutter 自动增加 1000 * ABI_VERSION；构建传入 -P force-version-code-ignoring-abi=true 可强制使用原版本号。参考 https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter 默认筛选包含全部三个 ABI，即使 --target-platform 只指定一个。排除仅插件提供的 ABI，避免安装器选中缺少 Flutter 或 Rust 核心的架构。
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

    packaging {
        jniLibs {
            // 可选的侧载 APK 压缩；Android 安装时解压这些库，以安装空间换取更小的下载体积。
            useLegacyPackaging = providers.gradleProperty("compress-native-libs")
                .orNull?.toBooleanStrict() ?: true
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.window:window:1.3.0")
    implementation("androidx.window:window-java:1.3.0")
}
