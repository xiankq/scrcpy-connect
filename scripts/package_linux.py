"""Package a verified Flutter bundle as DEB, RPM and AppImage."""
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

APP_ID = "dev.scrcpyconnect.scrcpy_connect"
TOOL_SHA256 = {
    "x86_64": "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0",
    "aarch64": "f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158",
}
RUNTIME_SHA256 = {
    "x86_64": "2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d",
    "aarch64": "00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444",
}


def download(url, destination, expected):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"SHA256 mismatch: {url}")
    destination.write_bytes(data)


def main(bundle, prefix, arch, version):
    machine, deb_arch = {"x64": ("x86_64", "amd64"), "arm64": ("aarch64", "arm64")}[arch]
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="interconnect-linux-") as temp:
        work = Path(temp)
        root = work / "root"
        app = root / "opt/interconnect"
        shutil.copytree(bundle, app, symlinks=True)
        shutil.copytree(app / "share", root / "usr/share")
        command = root / "usr/bin/interconnect"
        command.parent.mkdir()
        # 相对链接同时适用于系统安装与 AppImage 解包运行。
        command.symlink_to("../../opt/interconnect/interconnect")

        control = root / "DEBIAN/control"
        control.parent.mkdir()
        control.write_text(f"""Package: interconnect
Version: {version}
Architecture: {deb_arch}
Maintainer: Interconnect contributors
Section: utils
Priority: optional
Depends: libc6 (>= 2.39), libgtk-3-0t64 | libgtk-3-0, libepoxy0, libdrm2, libva2, libva-drm2, libstdc++6, adb
Description: Cross-device Android control and file workspace
""")
        deb = str(prefix) + ".deb"
        subprocess.run(["dpkg-deb", "--root-owner-group", "--build", root, deb], check=True)
        subprocess.run(["dpkg-deb", "--contents", deb], stdout=subprocess.DEVNULL, check=True)
        shutil.rmtree(control.parent)

        rpm_top = work / "rpm"
        rpm_top.mkdir()
        spec = work / "interconnect.spec"
        spec.write_text(f"""%global __os_install_post %{{nil}}
Name: interconnect
Version: {version}
Release: 1
Summary: Cross-device Android control and file workspace
License: See repository LICENSE
Requires: android-tools
%description
Control Android devices and transfer files.
%install
mkdir -p "%{{buildroot}}"
cp -a "{root}/." "%{{buildroot}}/"
%files
/opt/interconnect
/usr/bin/interconnect
/usr/share/applications/{APP_ID}.desktop
/usr/share/icons/hicolor/scalable/apps/{APP_ID}.svg
""")
        subprocess.run(["rpmbuild", "-bb", "--target", machine, "--define",
                        f"_topdir {rpm_top}", spec], check=True)
        rpm = str(prefix) + ".rpm"
        shutil.copyfile(next((rpm_top / "RPMS").glob("*/*.rpm")), rpm)
        subprocess.run(["rpm", "-qlp", rpm], stdout=subprocess.DEVNULL, check=True)

        desktop = root / f"{APP_ID}.desktop"
        shutil.copyfile(root / f"usr/share/applications/{desktop.name}", desktop)
        shutil.copyfile(root / f"usr/share/icons/hicolor/scalable/apps/{APP_ID}.svg",
                        root / f"{APP_ID}.svg")
        launch = root / "AppRun"
        launch.write_text(
            '#!/bin/sh\nset -eu\n'
            'app_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
            'exec "$app_dir/opt/interconnect/interconnect" "$@"\n'
        )
        launch.chmod(0o755)
        tool, runtime = work / "appimagetool", work / "runtime"
        host = platform.machine()
        download(f"https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-{host}.AppImage",
                 tool, TOOL_SHA256[host])
        download(f"https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-{machine}",
                 runtime, RUNTIME_SHA256[machine])
        tool.chmod(0o755)
        image = str(prefix) + ".AppImage"
        env = dict(os.environ, ARCH=machine, APPIMAGE_EXTRACT_AND_RUN="1")
        subprocess.run([tool, "--runtime-file", runtime, root, image], env=env, check=True)
        subprocess.run(["unsquashfs", "-offset", str(runtime.stat().st_size),
                        image, "AppRun"], cwd=work, stdout=subprocess.DEVNULL,
                       check=True)
        if (work / "squashfs-root/AppRun").read_bytes() != launch.read_bytes():
            raise ValueError("AppImage launcher does not match the package input")


if __name__ == "__main__":
    source, output, architecture, tag = sys.argv[1:]
    main(Path(source).resolve(), Path(output).resolve(), architecture, tag)
