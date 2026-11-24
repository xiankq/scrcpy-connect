"""Stage timing and diagnostics for release scripts."""
from contextlib import contextmanager
import os
import sys
from time import monotonic


@contextmanager
def stage(label):
    start = monotonic()
    print(f"INFO [{label}] Started", flush=True)
    try:
        yield
    except Exception as error:
        message = f"[{label}] Failed after {monotonic() - start:.2f}s. {error}"
        print(f"ERROR {message}", file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error::{escaped}", flush=True)
        raise SystemExit(1) from None
    print(f"INFO [{label}] Completed in {monotonic() - start:.2f}s", flush=True)
