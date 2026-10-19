#!/usr/bin/env python3
"""Build the single scrcpy server from pinned, unmodified upstream Java sources.

--check needs only Python. --rebuild compares a clean source build without writing
the repository; --update replaces the artifact and provenance after validation.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
VERSION = "5.0.1"
COMMIT = "a60891aea193d92e7e5c3942700eca63f9d19a5f"
SOURCE_SHA = "a0d699fc7388b8252416c49e6293639de39ab76a03e7302ddced56c284d45200"
OFFICIAL_SHA = "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536"
GRADLE_VERSION = "9.3.1"
GRADLE_SHA = "b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06"
DESUGAR_COMMIT = "50d9c1fb3e85fa4c00161525a45484f712c1f003"
DESUGAR_SOURCE_SHA = "70d37b80e367a57f642597aec25dd2a1d30a30817148eb978f2a02579db97278"
DESUGAR_SOURCE_NAME = "desugar_jdk_libs-2.1.4-source.tar.gz"
ARTIFACT = HERE / f"scrcpy-server-v{VERSION}"
MANIFEST = HERE / "manifest.json"
DEPS = {
    "desugar_jdk_libs": "d7604feeef3a771d5d616b68fcc2c42f516243311ea286cfd41e1962829a6d28",
    "desugar_jdk_libs_configuration": "5d770c1ba225c2cdf09086bf662954ae765ee481f901b02cd7b1dc3c8077c3f4",
}
ANDROID_JAR_SHA = "d9eb9da824d9e247a352f570f01e1169e725b2954bca9e283a71786c59b59f9a"
BUILD_ADDITION = """
// Build-only core library API desugaring. Upstream Java sources are unchanged.
android {
    buildToolsVersion '36.0.0'
    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
"""


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def download(url, expected):
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    require(sha(data) == expected, f"Download SHA-256 mismatch: {url}")
    return data


def source_url(commit, project="Genymobile/scrcpy"):
    return f"https://codeload.github.com/{project}/tar.gz/{commit}"


def dex_info(data):
    """Read class/interface tables and tool markers, not a string-only heuristic."""
    require(data[:8] == b"dex\n035\0", "Expected Android 5 compatible DEX 035")
    require(len(data) >= 112, "Truncated DEX")
    require(hashlib.sha1(data[32:]).digest() == data[12:32], "Invalid DEX signature")
    u32 = lambda offset: struct.unpack_from("<I", data, offset)[0]
    u16 = lambda offset: struct.unpack_from("<H", data, offset)[0]
    strings = []
    for i in range(u32(56)):
        offset = u32(u32(60) + 4 * i)
        while data[offset] & 128:
            offset += 1
        offset += 1
        strings.append(data[offset:data.index(b"\0", offset)].decode("utf-8", "replace"))
    types = [strings[u32(u32(68) + 4 * i)] for i in range(u32(64))]
    definitions = {}
    for i in range(u32(96)):
        offset = u32(100) + 32 * i
        interface_offset = u32(offset + 12)
        interfaces = [] if not interface_offset else [
            types[u16(interface_offset + 4 + 2 * j)]
            for j in range(u32(interface_offset))
        ]
        definitions[types[u32(offset)]] = interfaces
    markers = [s for s in strings if re.match(r"~~(?:D8|L8|R8)\{", s)]
    require(markers, "Missing D8/L8/R8 build provenance")
    for marker in markers:
        metadata = json.loads(marker[4:])
        require(metadata.get("min-api") == 21, "DEX was not built with min API 21")
        require(metadata.get("version") == "9.1.31", "Unexpected D8/L8/R8 version")
    return definitions, types, markers


def verify_artifact(data):
    definitions = {}
    references = set()
    dex = {}
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        dex_names = sorted(n for n in names if re.fullmatch(r"classes(?:[2-9][0-9]*)?\.dex", n))
        require(dex_names == ["classes.dex", "classes2.dex"], "Expected both program and backfill DEX")
        for name in dex_names:
            content = archive.read(name)
            classes, types, markers = dex_info(content)
            require(not definitions.keys() & classes.keys(), "Duplicate DEX class definitions")
            definitions.update(classes)
            references.update(types)
            dex[name] = {"sha256": sha(content), "classes": len(classes), "markers": markers}
        for name in license_files():
            require(archive.read("META-INF/" + name) == (HERE / name).read_bytes(), f"Missing/changed embedded license: {name}")
    required = [
        "Lcom/genymobile/scrcpy/Server;",
        "Lcom/genymobile/scrcpy/model/Size;",
        "Ljava/util/function/Predicate;",
        "Ljava/util/function/Supplier;",
        "Lj$/util/function/Predicate$-CC;",
    ]
    for name in required:
        require(name in definitions, f"Missing runtime class definition: {name}")
    name = "Lcom/genymobile/scrcpy/model/Size$$ExternalSyntheticLambda0;"
    require(definitions.get(name) == ["Ljava/util/function/Predicate;"], "Unexpected Size lambda interface")
    missing = sorted(t for t in references if t.startswith("Ljava/util/function/") and t not in definitions)
    require(not missing, f"Unresolved function backfill classes: {missing}")
    return dex


def license_files():
    return ["LICENSE-scrcpy", "LICENSE-desugar_jdk_libs", "ASSEMBLY_EXCEPTION-desugar_jdk_libs",
            "ADDITIONAL_LICENSE_INFO-desugar_jdk_libs", "LICENSE-desugar_jdk_libs_configuration"]


def package(apk):
    output = io.BytesIO()
    with zipfile.ZipFile(apk) as source, zipfile.ZipFile(output, "w") as target:
        contents = {n: source.read(n) for n in source.namelist() if n.endswith(".dex")}
        contents.update({"META-INF/" + n: (HERE / n).read_bytes() for n in license_files()})
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED
            target.writestr(info, data)
    return output.getvalue()


def tracked_inputs():
    names = ["build.py", "test/ScrcpyApi21Probe.java", "test/build_probe.py"] + license_files()
    return {name: sha((HERE / name).read_bytes()) for name in names}


def check():
    manifest = json.loads(MANIFEST.read_text())
    require(manifest["version"] == VERSION and manifest["source"]["commit"] == COMMIT, "Source version mismatch")
    require(manifest["source"]["archiveSha256"] == SOURCE_SHA, "Source pin mismatch")
    require(manifest["officialRelease"]["sha256"] == OFFICIAL_SHA, "Official release provenance mismatch")
    require(manifest["inputs"] == tracked_inputs(), "Build/test/license inputs changed; rebuild vendor artifact")
    require(sha((HERE / DESUGAR_SOURCE_NAME).read_bytes()) == DESUGAR_SOURCE_SHA, "Corresponding source archive mismatch")
    data = ARTIFACT.read_bytes()
    require(manifest["artifact"]["sha256"] == sha(data), "Server artifact SHA-256 mismatch")
    require(manifest["artifact"]["bytes"] == len(data), "Server artifact size mismatch")
    require(manifest["dex"] == verify_artifact(data), "DEX provenance mismatch")
    print(f"OK scrcpy {VERSION}, min API 21, program + function backfill; SHA-256 {sha(data)}")


def get_gradle(args, temporary):
    if args.gradle:
        gradle = Path(args.gradle).resolve()
    else:
        archive = download(f"https://services.gradle.org/distributions/gradle-{GRADLE_VERSION}-bin.zip", GRADLE_SHA)
        with zipfile.ZipFile(io.BytesIO(archive)) as source:
            # This archive is authenticated by the fixed SHA-256 above.
            source.extractall(temporary)
        gradle = temporary / f"gradle-{GRADLE_VERSION}/bin/gradle"
        gradle.chmod(0o755)
    result = subprocess.run([str(gradle), "--version"], check=True, capture_output=True, text=True)
    require(f"Gradle {GRADLE_VERSION}\n" in result.stdout, "Gradle version mismatch")
    return gradle


def build(args):
    sdk = Path(args.sdk or os.environ.get("ANDROID_HOME", "")).resolve()
    java_home = Path(os.environ.get("JAVA_HOME", "")).resolve()
    require((java_home / "bin/javac").is_file(), "Set JAVA_HOME to OpenJDK 21")
    java_version = subprocess.run([str(java_home / "bin/java"), "-version"], check=True, capture_output=True, text=True).stderr
    require('version "21.' in java_version, "OpenJDK 21 is required")
    android_jar = sdk / "platforms/android-36/android.jar"
    require(android_jar.is_file() and sha(android_jar.read_bytes()) == ANDROID_JAR_SHA, "Install the pinned Android API 36 platform")
    require((sdk / "build-tools/36.0.0/aapt2").is_file(), "Install Android build-tools 36.0.0")
    with tempfile.TemporaryDirectory(prefix="scrcpy-vendor-build-") as directory:
        temporary = Path(directory)
        gradle = get_gradle(args, temporary)
        source = download(source_url(COMMIT), SOURCE_SHA)
        with tarfile.open(fileobj=io.BytesIO(source), mode="r:gz") as archive:
            # Fixed upstream archive, plus reject links and traversal explicitly.
            for member in archive.getmembers():
                require(not member.issym() and not member.islnk(), "Unexpected source symlink")
                require(not Path(member.name).is_absolute() and ".." not in Path(member.name).parts, "Unsafe source path")
            archive.extractall(temporary, filter="data")
        root = temporary / f"scrcpy-{COMMIT}"
        java_sources = {str(p.relative_to(root)): sha(p.read_bytes()) for p in sorted((root / "server/src").rglob("*.java"))}
        build_file = root / "server/build.gradle"
        build_file.write_text(build_file.read_text() + BUILD_ADDITION)
        # Use environment variables rather than encoding host paths in Java properties.
        env = dict(os.environ, ANDROID_HOME=str(sdk))
        command = [str(gradle), "--no-daemon", "--max-workers=2", ":server:assembleRelease"]
        if args.offline:
            command.append("--offline")
        for value in args.gradle_arg:
            command.append(value)
        subprocess.run(command, cwd=root, env=env, check=True)
        require(java_sources == {str(p.relative_to(root)): sha(p.read_bytes()) for p in sorted((root / "server/src").rglob("*.java"))}, "Upstream Java source changed")
        gradle_home = Path(os.environ.get("GRADLE_USER_HOME", str(Path.home() / ".gradle")))
        for name, expected in DEPS.items():
            jars = list((gradle_home / f"caches/modules-2/files-2.1/com.android.tools/{name}/2.1.4").glob("*/*.jar"))
            require(bool(jars) and all(sha(p.read_bytes()) == expected for p in jars), f"Desugar dependency SHA mismatch: {name}")
        data = package(root / "server/build/outputs/apk/release/server-release-unsigned.apk")
        dex = verify_artifact(data)
        if args.rebuild:
            require(data == ARTIFACT.read_bytes(), f"Clean build differs: {sha(data)} != {sha(ARTIFACT.read_bytes())}")
            print("OK clean source rebuild is byte-for-byte identical")
            return
        manifest = {
            "schema": 1, "version": VERSION, "kind": "source-built-core-library-desugared",
            "source": {"commit": COMMIT, "archiveUrl": source_url(COMMIT), "archiveSha256": SOURCE_SHA, "javaSourcesSha256": sha(json.dumps(java_sources, sort_keys=True).encode()), "javaSourcesUnmodified": True},
            "officialRelease": {"url": f"https://github.com/Genymobile/scrcpy/releases/download/v{VERSION}/scrcpy-server-v{VERSION}", "sha256": OFFICIAL_SHA, "bundled": False},
            "artifact": {"file": ARTIFACT.name, "sha256": sha(data), "bytes": len(data)},
            "toolchain": {"gradle": GRADLE_VERSION, "gradleDistributionSha256": GRADLE_SHA, "agp": "9.1.0", "d8L8R8": "9.1.31", "jdkMajor": 21, "buildJdk": java_version.splitlines()[0], "compileSdk": 36, "androidJarSha256": ANDROID_JAR_SHA, "buildTools": "36.0.0", "minApi": 21, "targetApi": 36, "javaSourceTarget": "1.8"},
            "desugaring": {"version": "2.1.4", "dependencies": {"com.android.tools:" + name: {"version": "2.1.4", "sha256": digest} for name, digest in DEPS.items()}, "sourceCommit": DESUGAR_COMMIT, "sourceArchive": DESUGAR_SOURCE_NAME, "sourceUrl": source_url(DESUGAR_COMMIT, "google/desugar_jdk_libs"), "sourceSha256": DESUGAR_SOURCE_SHA, "functionStrategy": "Official maintain_type: java.util.function definitions in classes2.dex; default methods in j$.util.function"},
            "dex": dex, "inputs": tracked_inputs(),
        }
        # Keep the existing artifact intact until the new build passes every check.
        staging = ARTIFACT.with_suffix(".new")
        try:
            staging.write_bytes(data)
            staging.replace(ARTIFACT)
        finally:
            staging.unlink(missing_ok=True)
        MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        check()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="Offline artifact, DEX, source and input freshness checks")
    action.add_argument("--rebuild", action="store_true", help="Clean source build; compare byte-for-byte without modifying vendor")
    action.add_argument("--update", action="store_true", help="Clean source build; replace artifact and manifest after verification")
    parser.add_argument("--sdk", help="Android SDK root (default ANDROID_HOME)")
    parser.add_argument("--gradle", help="Existing Gradle 9.3.1 executable; otherwise download fixed distribution")
    parser.add_argument("--offline", action="store_true", help="Use Gradle's populated dependency cache")
    parser.add_argument("--gradle-arg", action="append", default=[], help="Additional Gradle argument, e.g. --gradle-arg=-Dhttps.proxyHost=")
    args = parser.parse_args()
    if args.check:
        check()
    else:
        require(sha((HERE / DESUGAR_SOURCE_NAME).read_bytes()) == DESUGAR_SOURCE_SHA, "Corresponding source archive missing/changed")
        build(args)


if __name__ == "__main__":
    main()
