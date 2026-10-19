import 'dart:io';

import 'package:path/path.dart' as path;

import 'src/host.dart';

Future<void> main() async {
  Directory? temporary;
  try {
    final root = repositoryRoot();
    var cmake = executable('cmake');
    if (cmake == null) {
      final sdk =
          Platform.environment['ANDROID_HOME'] ??
          Platform.environment['ANDROID_SDK_ROOT'] ??
          path.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE']!,
            'Android',
            'Sdk',
          );
      final versions = Directory(path.join(sdk, 'cmake'));
      final candidates = versions.existsSync()
          ? versions.listSync().whereType<Directory>().toList()
          : <Directory>[];
      candidates.sort((a, b) {
        final av = path.basename(a.path).split('.').map(int.tryParse).toList();
        final bv = path.basename(b.path).split('.').map(int.tryParse).toList();
        for (var i = 0; i < av.length || i < bv.length; i++) {
          final compared = (i < bv.length ? bv[i] ?? 0 : 0).compareTo(
            i < av.length ? av[i] ?? 0 : 0,
          );
          if (compared != 0) return compared;
        }
        return 0;
      });
      for (final directory in candidates) {
        final file = File(
          path.join(
            directory.path,
            'bin',
            Platform.isWindows ? 'cmake.exe' : 'cmake',
          ),
        );
        if (file.existsSync()) {
          cmake = file.path;
          break;
        }
      }
    }
    if (cmake == null) {
      throw StateError(
        'Install CMake (including CTest), or Android SDK CMake.',
      );
    }
    temporary = Directory.systemTemp.createTempSync('interop-fvp-cmake-');
    await runChecked(cmake, [
      '-S',
      path.join(root.path, 'third_party/fvp/cmake/tests'),
      '-B',
      temporary.path,
    ]);
    await runChecked(
      path.join(
        path.dirname(cmake),
        Platform.isWindows ? 'ctest.exe' : 'ctest',
      ),
      ['--test-dir', temporary.path, '--output-on-failure'],
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary?.deleteSync(recursive: true);
  }
}
