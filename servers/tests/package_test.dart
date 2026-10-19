import 'dart:io';

import 'package:path/path.dart' as p;

import '../package.dart';
import '../tooling.dart';

Future<void> rejects(void Function() action, String reason) async {
  try {
    action();
  } on StateError catch (error) {
    require(error.toString().contains(reason), 'Wrong rejection: $error');
    return;
  }
  throw StateError('Expected rejection: $reason');
}

Future<void> main(List<String> arguments) => cli(() async {
  require(arguments.isEmpty, 'No test arguments are accepted');
  final root = repositoryRoot();
  packageServers(root, check: true);
  await withTemporary('server-package-test-', (work) async {
    const inputs = [
      'servers/vendor/manifest.json',
      'servers/vendor/scrcpy-server-v5.0.1',
      'servers/companion/manifest.json',
      'servers/companion/companion.jar',
      'servers/helpers/manifest.json',
      'servers/helpers/bin/arm64-v8a/interop-rename',
      'servers/helpers/bin/armeabi-v7a/interop-rename',
      'servers/helpers/bin/x86_64/interop-rename',
      'servers/helpers/bin/x86/interop-rename',
    ];
    for (final path in inputs) {
      final target = File(p.join(work.path, path));
      target.parent.createSync(recursive: true);
      File(p.join(root.path, path)).copySync(target.path);
    }
    await rejects(() => packageServers(work, check: true), 'missing or stale');
    require(
      !Directory(p.join(work.path, packagedServerDirectory)).existsSync(),
      'Check wrote output',
    );
    packageServers(work);
    final output = Directory(p.join(work.path, packagedServerDirectory));
    final expected = <String, String>{
      for (final file in output.listSync().cast<File>())
        p.basename(file.path): digest(file),
    };
    packageServers(work);
    packageServers(work, check: true);
    for (final file in output.listSync().cast<File>()) {
      require(
        digest(file) == expected[p.basename(file.path)],
        'Nondeterministic packaging',
      );
    }
    final stale = File(p.join(output.path, 'obsolete.zlib'))
      ..writeAsStringSync('stale');
    await rejects(() => packageServers(work, check: true), 'Unexpected');
    require(stale.readAsStringSync() == 'stale', 'Check mutated stale output');
    packageServers(work);
    require(!stale.existsSync(), 'Generation retained stale output');
    final payload = File(p.join(output.path, 'scrcpy.zlib'))
      ..writeAsStringSync('bad compressed bytes');
    await rejects(() => packageServers(work, check: true), 'missing or stale');
    require(
      payload.readAsStringSync() == 'bad compressed bytes',
      'Check repaired output',
    );
    packageServers(work);
    for (final path in inputs.where(
      (path) => !path.endsWith('manifest.json'),
    )) {
      final input = File(p.join(work.path, path));
      final bytes = input.readAsBytesSync();
      input.writeAsStringSync('tampered controlled input');
      await rejects(() => packageServers(work), 'differs from its manifest');
      input.writeAsBytesSync(bytes);
    }
    packageServers(work, check: true);
  });
  stdout.writeln(
    'PASS: deterministic server packaging, read-only drift checks, stale removal and all six input SHA checks',
  );
});
