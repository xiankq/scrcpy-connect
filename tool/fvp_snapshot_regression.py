#!/usr/bin/env python3
"""Exercise fvp's actual MdkSnapshot body at the MDK callback boundary.

No renderer or SDK is substituted into the product. This host-only probe injects
the documented nullable result and checks the real Dart_CObject wire format.
Use --package-root with an unmodified fvp 0.39.1 archive to observe SIGSEGV.
"""

import argparse
import hashlib
from pathlib import Path
import resource
import subprocess
import tempfile


COPIES = (
    "lib/src/callbacks.cpp",
    "darwin/Classes/callbacks.cpp",
    "darwin/fvp/Sources/fvp/callbacks.cpp",
    "ios/Classes/callbacks.cpp",
    "macos/Classes/callbacks.cpp",
)

PRELUDE = r'''
#include <functional>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <unordered_map>
#include "dart_api_types.h"
#include "callbacks.h"
using namespace std;
static bool failed = true;
static unsigned char pixels[48] = {11, 22, 33, 255};
struct Player {
    struct SnapshotRequest {
        unsigned char* data = nullptr;
        int width = 0, height = 0, stride = 0;
    };
    void snapshot(SnapshotRequest*,
                  function<string(const SnapshotRequest*, double)> callback) {
        // MDK may return null on failure. A valid buffer can have row padding.
        SnapshotRequest result{pixels, 3, 3, 16};
        callback(failed ? nullptr : &result, 0.0);
    }
};
static unordered_map<int64_t, shared_ptr<Player>> players;
static uint64_t currentDartPostGeneration() { return 0; }
static bool postToDart(Dart_PostCObject post, Dart_Port port,
                       Dart_CObject* message, uint64_t) {
    return post(port, message);
}
static int posted = 0;
static bool receive(Dart_Port port, Dart_CObject* message) {
    if (port != 7 || message->type != Dart_CObject_kArray ||
        message->value.as_array.length != 2) return false;
    const auto* event = message->value.as_array.values[0];
    const auto* data = message->value.as_array.values[1];
    if (event->type != Dart_CObject_kInt64 ||
        event->value.as_int64 != CallbackType::Snapshot ||
        data->type != Dart_CObject_kTypedData ||
        data->value.as_typed_data.type != Dart_TypedData_kUint8) return false;
    const auto& bytes = data->value.as_typed_data;
    // Empty Uint8List is fvp player.dart's nullable snapshot completion signal.
    if (bytes.length != (failed ? 0 : sizeof(pixels)) ||
        bytes.values != (failed ? nullptr : pixels)) return false;
    ++posted;
    return true;
}
'''

EPILOGUE = r'''
FVP_EXPORT int RunSnapshotProbe(void* post, int64_t port) {
    players[42] = make_shared<Player>();
    failed = true;
    if (!MdkSnapshot(42, 0, 3, 3, post, port)) return 1;
    failed = false;
    if (!MdkSnapshot(42, 0, 3, 3, post, port)) return 2;
    return 0;
}
int main() {
    players[42] = make_shared<Player>();
    auto post = reinterpret_cast<void*>(receive);
    if (MdkSnapshot(99, 0, 3, 3, post, 7) || posted != 0) return 1;
    if (!MdkSnapshot(42, 0, 3, 3, post, 7) || posted != 1) return 2;
    failed = false;
    if (!MdkSnapshot(42, 0, 3, 3, post, 7) || posted != 2) return 3;
    cout << "PASS: unknown handle, null completion, padded RGBA completion\n";
}
'''

DART_PROBE = r'''
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args.single);
  final probe = library.lookupFunction<
      Int32 Function(Pointer<Void>, Int64),
      int Function(Pointer<Void>, int)>('RunSnapshotProbe');
  final port = ReceivePort();
  try {
    final incoming = port.take(2).toList().timeout(const Duration(seconds: 3));
    final result = probe(NativeApi.postCObject.cast<Void>(), port.sendPort.nativePort);
    if (result != 0) throw StateError('Native request failed: $result');
    final messages = await incoming;
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i] as List<dynamic>;
      if (message.length != 2 || message[0] != 7 || message[1] is! Uint8List) {
        throw StateError('Invalid snapshot message: $message');
      }
      final bytes = message[1] as Uint8List;
      if (i == 0 ? bytes.isNotEmpty :
          bytes.length != 48 || bytes[0] != 11 || bytes[1] != 22 || bytes[3] != 255) {
        throw StateError('Invalid snapshot data at index $i');
      }
    }
    print('PASS: real Dart_PostCObject delivered empty and populated Uint8List');
  } finally {
    port.close();
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package-root", type=Path,
        default=Path(__file__).resolve().parents[1] / "third_party/fvp",
    )
    parser.add_argument("--cxx", default="c++")
    parser.add_argument("--dart", default="dart")
    args = parser.parse_args()
    root = args.package_root.resolve()
    sources = [(root / name).read_bytes() for name in COPIES]
    if len(set(sources)) != 1:
        raise SystemExit("FAIL: platform callback copies differ")
    source = sources[0].decode()
    marker = 'FVP_EXPORT bool MdkSnapshot('
    if source.count(marker) != 1:
        raise SystemExit("FAIL: expected one actual MdkSnapshot source body")
    body = source[source.index(marker):]
    print("callbacks.cpp SHA-256:", hashlib.sha256(sources[0]).hexdigest(), flush=True)
    print("Scope: native source seam; not an MDK renderer/device test", flush=True)
    with tempfile.TemporaryDirectory(prefix="connect-fvp-snapshot-") as directory:
        fixture = Path(directory) / "fixture.cpp"
        binary = Path(directory) / "probe"
        fixture.write_text(PRELUDE + body + EPILOGUE)
        subprocess.run([
            args.cxx, "-std=c++20", "-O0", "-I", str(root / "lib/src"),
            str(fixture), "-o", str(binary),
        ], check=True)
        # A known-bad upstream body must not leave a large core dump behind.
        def no_core():
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        result = subprocess.run([str(binary)], preexec_fn=no_core)
        if result.returncode:
            raise SystemExit(f"FAIL: snapshot boundary probe exited {result.returncode}")
        library = Path(directory) / "probe.so"
        dart = Path(directory) / "probe.dart"
        dart.write_text(DART_PROBE)
        subprocess.run([
            args.cxx, "-std=c++20", "-O0", "-shared", "-fPIC",
            "-I", str(root / "lib/src"), str(fixture), "-o", str(library),
        ], check=True)
        subprocess.run([args.dart, str(dart), str(library)], check=True,
                       timeout=20, preexec_fn=no_core)


if __name__ == "__main__":
    main()
