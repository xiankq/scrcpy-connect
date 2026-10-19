#!/usr/bin/env python3
"""Exercise compatibility boundaries on the host without an Android device."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or Path.home() / "Android/Sdk")
ANDROID = SDK / "platforms/android-36/android.jar"
with tempfile.TemporaryDirectory(prefix="companion-compatibility-") as directory:
    subprocess.run(["javac", "--release", "8", "-cp", str(ANDROID), "-d", directory,
                    *map(str, sorted(ROOT.glob("src/**/*.java"))), str(ROOT / "tests/CompatibilityTest.java")], check=True)
    classes = [str(path.relative_to(directory).with_suffix("")).replace(os.sep, ".")
               for path in Path(directory).rglob("*.class") if not path.name.startswith("CompatibilityTest")]
    bytecode = subprocess.check_output(["javap", "-c", "-p", "-classpath", directory, *classes], text=True)
    # D8 --min-api controls dex/desugaring; it does not backport the platform's
    # Java 8 collection defaults. Validate the emitted invocation owner, since
    # ConcurrentMap.remove(key,value) exists on API21 while Map.remove does not.
    unsupported = re.findall(r"(?:InterfaceMethod|Method) (java/util/(?:Map\.remove:\(Ljava/lang/Object;Ljava/lang/Object;\)Z|(?:Map\.(?:replace|replaceAll|compute|computeIfAbsent|computeIfPresent|merge|getOrDefault|putIfAbsent|forEach)|Collection\.(?:removeIf|stream|parallelStream)|List\.(?:sort|replaceAll)):[^\n]+))", bytecode)
    assert not unsupported, "API21-incompatible Java collection defaults: " + repr(unsupported)
    common_thumbnail = subprocess.check_output(["javap", "-c", "-p", "-classpath", directory,
                                                "com.interop.companion.Thumbnail"], text=True)
    assert "android/media/MediaDataSource" not in common_thumbnail and "getScaledFrameAtTime" not in common_thumbnail, \
        "API21 image/stat class directly resolves a newer video API"
    assert "android/system/OsConstants.O_CLOEXEC" not in common_thumbnail, \
        "API21 has no OsConstants.O_CLOEXEC Java field"
    subprocess.run(["java", "-cp", directory + os.pathsep + str(ANDROID), "com.interop.companion.CompatibilityTest"], check=True)
