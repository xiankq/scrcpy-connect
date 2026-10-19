import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'src/host.dart';

const copies = [
  'lib/src/callbacks.cpp',
  'darwin/Classes/callbacks.cpp',
  'darwin/fvp/Sources/fvp/callbacks.cpp',
  'ios/Classes/callbacks.cpp',
  'macos/Classes/callbacks.cpp',
];

Future<void> main(List<String> arguments) async {
  Directory? temporary;
  try {
    final parser = ArgParser()
      ..addOption('package-root')
      ..addOption('cxx', defaultsTo: 'c++')
      ..addOption('dart', defaultsTo: Platform.resolvedExecutable);
    final args = parser.parse(arguments);
    final root = Directory(
      args.option('package-root') ??
          path.join(repositoryRoot().path, 'third_party/fvp'),
    ).absolute;
    final sources = copies
        .map((name) => File(path.join(root.path, name)).readAsBytesSync())
        .toList();
    if (sources.map(base64Encode).toSet().length != 1) {
      throw StateError('Platform callback copies differ.');
    }
    final source = utf8.decode(sources.first);
    const marker = 'FVP_EXPORT bool MdkSnapshot(';
    if (marker.allMatches(source).length != 1) {
      throw StateError('Expected one actual MdkSnapshot source body.');
    }
    final body = source.substring(source.indexOf(marker));
    stdout.writeln('callbacks.cpp SHA-256: ${sha256.convert(sources.first)}');
    stdout.writeln(
      'Scope: native source seam; not an MDK renderer/device test',
    );
    temporary = Directory.systemTemp.createTempSync('connect-fvp-snapshot-');
    final fixture = File(path.join(temporary.path, 'fixture.cpp'))
      ..writeAsStringSync(prelude + body + epilogue);
    final binary = path.join(temporary.path, 'probe');
    final cxx = args.option('cxx')!;
    await runChecked(cxx, [
      '-std=c++20',
      '-O0',
      '-I',
      path.join(root.path, 'lib/src'),
      fixture.path,
      '-o',
      binary,
    ]);
    // POSIX host probe: a deliberately broken upstream must not leave a core dump.
    await runChecked('/bin/sh', [
      '-c',
      r'ulimit -c 0; exec "$@"',
      'snapshot-probe',
      binary,
    ]);
    final library = path.join(
      temporary.path,
      Platform.isMacOS ? 'probe.dylib' : 'probe.so',
    );
    final dart = File(path.join(temporary.path, 'probe.dart'))
      ..writeAsStringSync(dartProbe);
    await runChecked(cxx, [
      '-std=c++20',
      '-O0',
      '-shared',
      '-fPIC',
      '-I',
      path.join(root.path, 'lib/src'),
      fixture.path,
      '-o',
      library,
    ]);
    await runChecked('/bin/sh', [
      '-c',
      r'ulimit -c 0; exec "$@"',
      'snapshot-dart',
      args.option('dart')!,
      dart.path,
      library,
    ], timeout: const Duration(seconds: 20));
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary?.deleteSync(recursive: true);
  }
}

const prelude = r'''
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
''';

const epilogue = r'''
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
''';

const dartProbe = r'''
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
''';
