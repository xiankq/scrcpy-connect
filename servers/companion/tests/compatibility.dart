import 'dart:io';

import 'package:path/path.dart' as p;

import '../../tooling.dart';

Future<void> main(List<String> arguments) => cli(() async {
  require(
    arguments.isEmpty,
    'This host compatibility check accepts no arguments',
  );
  final root = Directory(p.join(repositoryRoot().path, 'servers', 'companion'));
  final sdk = androidSdk();
  final android = p.join(sdk.path, 'platforms', 'android-36', 'android.jar');
  await withTemporary('companion-compatibility-', (directory) async {
    final classes = await compileJava(
      work: directory,
      sources: [
        ...files(Directory(p.join(root.path, 'src')), '.java'),
        File(p.join(root.path, 'tests', 'CompatibilityTest.java')),
      ],
      sdk: sdk,
    );
    final classNames = files(classes, '.class')
        .where((file) => !p.basename(file.path).startsWith('CompatibilityTest'))
        .map(
          (file) => p
              .withoutExtension(relative(file.path, classes.path))
              .replaceAll('/', '.'),
        );
    final bytecode =
        (await run(javaTool('javap'), [
              '-c',
              '-p',
              '-classpath',
              classes.path,
              ...classNames,
            ])).stdout
            as String;
    final unsupported = RegExp(
      r'(?:InterfaceMethod|Method) (java/util/(?:Map\.remove:\(Ljava/lang/Object;Ljava/lang/Object;\)Z|(?:Map\.(?:replace|replaceAll|compute|computeIfAbsent|computeIfPresent|merge|getOrDefault|putIfAbsent|forEach)|Collection\.(?:removeIf|stream|parallelStream)|List\.(?:sort|replaceAll)):[^\n]+))',
    ).allMatches(bytecode).map((match) => match.group(1)).toList();
    require(
      unsupported.isEmpty,
      'API21-incompatible Java collection defaults: $unsupported',
    );
    final thumbnail =
        (await run(javaTool('javap'), [
              '-c',
              '-p',
              '-classpath',
              classes.path,
              'com.interop.companion.Thumbnail',
            ])).stdout
            as String;
    require(
      !thumbnail.contains('android/media/MediaDataSource') &&
          !thumbnail.contains('getScaledFrameAtTime'),
      'API21 image/stat class directly resolves a newer video API',
    );
    require(
      !thumbnail.contains('android/system/OsConstants.O_CLOEXEC'),
      'API21 has no OsConstants.O_CLOEXEC Java field',
    );
    await run(javaTool('java'), [
      '-cp',
      '${classes.path}${Platform.isWindows ? ';' : ':'}$android',
      'com.interop.companion.CompatibilityTest',
    ], echo: true);
  });
});
