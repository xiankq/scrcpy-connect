import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../companion/build.dart' as companion;
import '../tooling.dart';
import '../vendor/build.dart' as vendor;

Future<void> rejects(Future<void> Function() action, String reason) async {
  try {
    await action();
  } on StateError catch (error) {
    require(
      error.message.toString().contains(reason),
      'Wrong rejection: $error',
    );
    return;
  }
  throw StateError('Expected rejection containing: $reason');
}

Future<void> main(List<String> arguments) => cli(() async {
  require(arguments.isEmpty, 'No test arguments are accepted');
  final root = repositoryRoot();
  final vendorBytes = File(
    p.join(root.path, 'servers', 'vendor', 'scrcpy-server-v5.0.1'),
  ).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(vendorBytes, verify: true);
  final entries = <String, List<int>>{
    for (final file in archive) file.name: archiveBytes(file),
  };
  Uint8List vendorZip() => storedZip({
    for (final name in entries.keys.toList()..sort()) name: entries[name]!,
  }, date: DateTime.utc(1980));
  require(
    sha256(vendorZip()) == sha256(vendorBytes),
    'Stored ZIP changed pinned vendor bytes',
  );
  vendor.verifyArtifact(vendorBytes);

  final corruptLocalCrc = Uint8List.fromList(vendorBytes)..[14] ^= 1;
  await rejects(() async {
    vendor.verifyArtifact(corruptLocalCrc);
  }, 'Corrupt ZIP entry');

  final duplicate = storedZip({
    'first.dex': [1],
    'other.dex': [2],
  }, date: DateTime.utc(1980));
  final oldName = utf8.encode('other.dex');
  final newName = utf8.encode('first.dex');
  for (var i = 0; i <= duplicate.length - oldName.length; i++) {
    if (List.generate(
      oldName.length,
      (j) => duplicate[i + j] == oldName[j],
    ).every((match) => match)) {
      duplicate.setRange(i, i + newName.length, newName);
    }
  }
  await rejects(() async {
    vendor.verifyArtifact(duplicate);
  }, 'Duplicate ZIP entries');

  final dex = Uint8List.fromList(entries['classes.dex']!);
  final needle = utf8.encode('"min-api":21');
  var marker = -1;
  for (var i = 0; i <= dex.length - needle.length; i++) {
    if (List.generate(
      needle.length,
      (j) => dex[i + j] == needle[j],
    ).every((match) => match)) {
      marker = i;
      break;
    }
  }
  require(marker >= 0, 'Missing known min-api marker');
  dex[marker + needle.length - 1] = 50; // 改为 API 22，保持 DEX 字符串偏移不变。
  dex.setRange(12, 32, crypto.sha1.convert(dex.sublist(32)).bytes);
  entries['classes.dex'] = dex;
  await rejects(() async {
    vendor.verifyArtifact(vendorZip());
  }, 'min API 21');
  await rejects(() async {
    vendor.dexInfo([100, 101, 120]);
  }, 'Truncated DEX');

  final companionJar = File(
    p.join(root.path, 'servers', 'companion', 'companion.jar'),
  );
  final companionArchive = ZipDecoder().decodeBytes(
    companionJar.readAsBytesSync(),
    verify: true,
  );
  final packaged = storedZip(
    {for (final file in companionArchive) file.name: archiveBytes(file)},
    date: DateTime.utc(2026, 10, 16),
    system: 0,
    attributes: (name) => name.endsWith('/') ? 0x10 : 0x20,
  );
  require(
    sha256(packaged) == digest(companionJar),
    'Stored ZIP changed pinned companion bytes',
  );

  await withTemporary('server-tooling-test-', (work) async {
    final corruptSource = File(p.join(work.path, 'source.tar.gz'));
    await corruptSource.writeAsBytes([1, 2, 3]);
    await rejects(() async {
      await vendor.sourceArchive(corruptSource.path);
    }, 'Source archive SHA-256 mismatch');
    final copy = Directory(p.join(work.path, 'servers', 'companion'))
      ..createSync(recursive: true);
    final original = Directory(p.join(root.path, 'servers', 'companion'));
    await File(p.join(root.path, 'servers', 'build.dart'))
        .copy(p.join(work.path, 'servers', 'build.dart'));
    final common = File(p.join(work.path, 'servers', 'tooling.dart'));
    await File(p.join(root.path, 'servers', 'tooling.dart')).copy(common.path);
    final repositoryTooling = File(
      p.join(work.path, 'scripts', 'src', 'repository_tooling.dart'),
    );
    await repositoryTooling.parent.create(recursive: true);
    await File(p.join(root.path, 'scripts', 'src', 'repository_tooling.dart'))
        .copy(repositoryTooling.path);
    await File(p.join(root.path, 'scripts', 'src', 'process.dart'))
        .copy(p.join(work.path, 'scripts', 'src', 'process.dart'));
    for (final source in [
      File(p.join(original.path, 'build.dart')),
      ...files(Directory(p.join(original.path, 'src')), '.java'),
    ]) {
      final destination = File(
        p.join(copy.path, relative(source.path, original.path)),
      );
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
    }
    final jar = await companionJar.copy(p.join(copy.path, 'companion.jar'));
    final manifest = File(p.join(copy.path, 'manifest.json'));
    writeJson(manifest, {
      'tools': companion.tools,
      'sources': companion.inputs(copy),
      'artifact': {'sha256': digest(jar), 'size': jar.lengthSync()},
    });
    await companion.verifyManifest(copy);
    final javaSource = files(
      Directory(p.join(copy.path, 'src')),
      '.java',
    ).first;
    for (final source in [
      javaSource,
      File(p.join(copy.path, 'build.dart')),
      common,
      repositoryTooling,
    ]) {
      final bytes = source.readAsBytesSync();
      await source.writeAsString('// altered\n', mode: FileMode.append);
      await rejects(
        () => companion.verifyManifest(copy),
        'sources or build tools changed',
      );
      await source.writeAsBytes(bytes);
    }
    await jar.writeAsString('altered');
    await rejects(() => companion.verifyManifest(copy), 'JAR differs');

    final extraction = Directory(p.join(work.path, 'extract'))..createSync();
    final malicious = Archive()..addFile(ArchiveFile('../escape', 1, [1]));
    await rejects(
      () => extractArchive(malicious, extraction),
      'Unsafe archive path',
    );
    require(
      !File(p.join(work.path, 'escape')).existsSync(),
      'Archive escaped its extraction root',
    );
    for (final link in [
      ArchiveFile.symlink('link', '../escape'),
      ArchiveFile.symlink('empty-link', ''),
    ]) {
      await rejects(
        () => extractArchive(Archive()..addFile(link), extraction),
        'Unexpected archive link',
      );
      require(
        !FileSystemEntity.isLinkSync(p.join(extraction.path, link.name)),
        'Archive created a symbolic link',
      );
    }
  });
  stdout.writeln(
    'PASS: pinned ZIP bytes, duplicate ZIP/min-api rejection, manifest script/shared-tool/repository-tool/JAR drift, archive traversal and symbolic links',
  );
});
