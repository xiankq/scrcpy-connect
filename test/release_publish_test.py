import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


PUBLISH = Path(__file__).resolve().parents[1] / "scripts/publish_release.sh"
TAG = "v0.1.0-preview.2"


class ReleasePublishTest(unittest.TestCase):
    def test_retry_reuses_matching_asset_and_checks_uploaded_digests(self):
        for corrupt in (False, True):
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                files = {"keep.apk": b"existing APK", "replace.apk": b"fresh APK"}
                for name, data in files.items():
                    (folder / name).write_bytes(data)
                digests = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
                (folder / "SHA256SUMS").write_text(
                    "".join(f"{digest}  {name}\n" for name, digest in digests.items())
                )
                notes = folder / "notes.md"
                notes.write_text("Preview notes.\n")
                (folder / "assets.json").write_text(json.dumps([
                    {"name": "keep.apk", "state": "uploaded", "digest": f"sha256:{digests['keep.apk']}"},
                    {"name": "replace.apk", "state": "uploaded", "digest": "sha256:outdated"},
                ]))
                gh = folder / "gh"
                gh.write_text("""#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
store = Path("assets.json")
assets = json.loads(store.read_text())
if args[:2] == ["api", "--paginate"]:
    print(json.dumps([{"tag_name": os.environ["GITHUB_REF_NAME"], "draft": True}]))
elif args[0] == "api":
    print(json.dumps(assets))
elif args[:2] == ["release", "view"]:
    print(7)
elif args[:2] == ["release", "upload"]:
    files = args[args.index("--clobber") + 1:]
    Path("uploaded").write_text("\\n".join(files))
    assets = [asset for asset in assets if asset["name"] not in files]
    for name in files:
        digest = hashlib.sha256(Path(name).read_bytes()).hexdigest()
        if name == "replace.apk" and os.environ["CORRUPT_UPLOAD"] == "true":
            digest = "wrong"
        assets.append({"name": name, "state": "uploaded", "digest": "sha256:" + digest})
    store.write_text(json.dumps(assets))
elif args[:2] == ["release", "edit"] and "--draft=false" in args:
    Path("published").touch()
""")
                gh.chmod(0o755)
                completed = subprocess.run(
                    ["bash", PUBLISH, folder, notes],
                    env={
                        **os.environ,
                        "PATH": f"{folder}{os.pathsep}{os.environ['PATH']}",
                        "GITHUB_REF_NAME": TAG,
                        "GITHUB_REPOSITORY": "test/interconnect",
                        "PREVIEW": "true",
                        "CORRUPT_UPLOAD": str(corrupt).lower(),
                    },
                    capture_output=True,
                    text=True,
                )
                details = completed.stdout + completed.stderr
                self.assertEqual(completed.returncode == 0, not corrupt, details)
                self.assertEqual((folder / "published").exists(), not corrupt, details)
                self.assertEqual(
                    set((folder / "uploaded").read_text().splitlines()),
                    {"replace.apk", "SHA256SUMS"},
                )
                if corrupt:
                    self.assertIn("ERROR [GitHub release/verify remote checksums]", details)
                    self.assertIn("Missing or mismatched: replace.apk", details)


if __name__ == "__main__":
    unittest.main()
