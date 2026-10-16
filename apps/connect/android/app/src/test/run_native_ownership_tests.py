#!/usr/bin/env python3
"""Compile the actual Kotlin ownership sources and exercise their hardware ports on the JVM.

Uses the project's already resolved Kotlin compiler, Android SDK and Flutter SDK;
no network, Android framework mocks, APK build, device, or Gradle mutation.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

android = Path(__file__).resolve().parents[3]
properties = dict(line.split("=", 1) for line in (android / "local.properties").read_text().splitlines() if "=" in line)
version = re.search(r'id\("org.jetbrains.kotlin.android"\) version "([^"]+)"', (android / "settings.gradle.kts").read_text()).group(1)
cache = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle")) / "caches/modules-2/files-2.1"

def artifact(group, name, version, extension="jar"):
    matches = list((cache / group / name / version).glob(f"*/{name}-{version}.{extension}"))
    if len(matches) != 1:
        raise SystemExit(f"Run the project's native Gradle compile first; missing local {name}:{version}")
    return matches[0]

compiler = artifact("org.jetbrains.kotlin", "kotlin-compiler-embeddable", version)
pom = ET.parse(artifact("org.jetbrains.kotlin", "kotlin-compiler-embeddable", version, "pom"))
ns = {"p": "http://maven.apache.org/POM/4.0.0"}
compiler_jars = [compiler]
for dependency in pom.findall("p:dependencies/p:dependency", ns):
    if dependency.findtext("p:scope", "compile", ns) in ("compile", "runtime"):
        compiler_jars.append(artifact(*(dependency.findtext("p:" + key, namespaces=ns) for key in ("groupId", "artifactId", "version"))))
annotations = sorted((cache / "org.jetbrains/annotations").glob("*/*/*.jar"))
if annotations:
    compiler_jars.append(annotations[-1])
stdlib = artifact("org.jetbrains.kotlin", "kotlin-stdlib", version)
sdk = Path(properties["sdk.dir"]) / "platforms/android-36/android.jar"
flutter = Path(properties["flutter.sdk"]) / "bin/cache/artifacts/engine/android-x64/flutter.jar"
if not sdk.is_file() or not flutter.is_file():
    raise SystemExit("Project Android 36 SDK and Flutter android-x64 engine cache are required")
source = android / "app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect"
test = android / "app/src/test/kotlin/dev/scrcpyconnect/scrcpy_connect/NativeOwnershipTest.kt"
java = str(Path(os.environ.get("JAVA_HOME", "/usr/lib/jvm/java-21-openjdk-amd64")) / "bin/java")
with tempfile.TemporaryDirectory(prefix="interop-audio-contracts-") as build:
    subprocess.run([java, "-Xmx768m", "-cp", os.pathsep.join(map(str, compiler_jars)),
        "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-no-stdlib", "-no-reflect", "-jvm-target", "17",
        "-classpath", os.pathsep.join(map(str, [stdlib, sdk, flutter])), "-d", build,
        str(source / "ShareImportPolicy.kt"), str(source / "AudioSessionOwnership.kt"), str(test)], check=True)
    # There is deliberately no android.jar or Flutter runtime here. Only the
    # production coordination and hardware ports execute, never framework stubs.
    subprocess.run([java, "-cp", build + os.pathsep + str(stdlib),
        "dev.scrcpyconnect.scrcpy_connect.NativeOwnershipTest"], check=True)
