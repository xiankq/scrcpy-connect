import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/bundled_servers.dart';

const _prefix = 'assets/servers/';
const _sources = {
  'scrcpy': 'servers/vendor/scrcpy-server-v5.0.1',
  'companion': 'servers/companion/companion.jar',
  'arm64-v8a': 'servers/helpers/bin/arm64-v8a/interop-rename',
  'armeabi-v7a': 'servers/helpers/bin/armeabi-v7a/interop-rename',
  'x86_64': 'servers/helpers/bin/x86_64/interop-rename',
  'x86': 'servers/helpers/bin/x86/interop-rename',
};

class _Bundle extends CachingAssetBundle {
  _Bundle(this.assets);

  final Map<String, Uint8List> assets;
  final loads = <String>[];
  Future<void> Function(String)? onLoad;

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    await onLoad?.call(key);
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing test asset: $key');
    return ByteData.sublistView(bytes);
  }

  void alterManifest(void Function(Map<String, dynamic>) change) {
    final manifest = jsonDecode(
      utf8.decode(assets['${_prefix}manifest.json']!),
    ) as Map<String, dynamic>;
    change(manifest);
    assets['${_prefix}manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest)),
    );
  }
}

void main() {
  late Directory root;
  late Directory work;
  late _Bundle bundle;
  late Map<String, Uint8List> original;
  late Map<String, Uint8List> assets;

  setUpAll(() {
    root = Directory.current.absolute;
    while (!File('${root.path}/Cargo.toml').existsSync()) {
      final parent = root.parent;
      if (parent.path == root.path) throw StateError('Repository root missing');
      root = parent;
    }
    original = {
      for (final source in _sources.entries)
        source.key: File('${root.path}/${source.value}').readAsBytesSync(),
    };
    assets = {
      for (final name in [
        'manifest.json',
        ..._sources.keys.map((id) => '$id.zlib'),
      ])
        '$_prefix$name': File('${root.path}/app/$_prefix$name')
            .readAsBytesSync(),
    };
  });

  setUp(() async {
    work = await Directory.systemTemp.createTemp('bundled-servers-test-');
    bundle = _Bundle(Map.from(assets));
  });
  tearDown(() => work.delete(recursive: true));

  test('restores all six controlled artifacts byte for byte and reuses valid files', () async {
    final servers = BundledServers(bundle: bundle);
    final restored = await servers.prepare(work);
    expect(restored.scrcpyBytes, original['scrcpy']);
    expect(restored.companionBytes, original['companion']);
    expect(
      restored.helperArtifacts.keys,
      unorderedEquals(['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']),
    );
    for (final entry in restored.helperArtifacts.entries) {
      expect(entry.value, original[entry.key]);
    }
    final dates = <String, DateTime>{};
    for (final entry in original.entries) {
      final file = File('${work.path}/bundled_servers/${entry.key}');
      expect(await file.readAsBytes(), entry.value);
      final date = DateTime.utc(2001);
      await file.setLastModified(date);
      dates[entry.key] = await file.lastModified();
    }
    bundle.loads.clear();
    final cached = await servers.prepare(work);
    expect(cached.scrcpyBytes, original['scrcpy']);
    expect(cached.companionBytes, original['companion']);
    expect(cached.helperArtifacts, restored.helperArtifacts);
    expect(bundle.loads, ['${_prefix}manifest.json']);
    for (final id in original.keys) {
      expect(
        await File('${work.path}/bundled_servers/$id').lastModified(),
        dates[id],
      );
    }
  });

  test(
    'returns immutable verified bytes independent of later cache changes',
    () async {
      final restored = await BundledServers(bundle: bundle).prepare(work);
      await File('${work.path}/bundled_servers/scrcpy').writeAsBytes([1, 2, 3]);
      expect(restored.scrcpyBytes, original['scrcpy']);
      expect(() => restored.scrcpyBytes[0] = 0, throwsUnsupportedError);
      expect(() => restored.helperArtifacts.clear(), throwsUnsupportedError);
      expect(
        () => restored.helperArtifacts['x86']![0] = 0,
        throwsUnsupportedError,
      );
    },
  );

  test('repairs damaged cache and restores missing cache', () async {
    final servers = BundledServers(bundle: bundle);
    await servers.prepare(work);
    await File('${work.path}/bundled_servers/scrcpy').writeAsBytes([1, 2, 3]);
    await File('${work.path}/bundled_servers/x86').delete();
    bundle.loads.clear();
    await servers.prepare(work);
    expect(
      await File('${work.path}/bundled_servers/scrcpy').readAsBytes(),
      original['scrcpy'],
    );
    expect(
      await File('${work.path}/bundled_servers/x86').readAsBytes(),
      original['x86'],
    );
    expect(bundle.loads, [
      '${_prefix}manifest.json',
      '${_prefix}scrcpy.zlib',
      '${_prefix}x86.zlib',
    ]);
    expect(
      (await Directory('${work.path}/bundled_servers').list().toList()).length,
      6,
    );
  });

  test('bounds highly compressible output by its declared size', () async {
    bundle.alterManifest((manifest) {
      ((manifest['artifacts'] as List).first as Map)['size'] = 1024;
    });
    bundle.assets['${_prefix}scrcpy.zlib'] = Uint8List.fromList(
      ZLibEncoder().convert(Uint8List(8 * 1024 * 1024)),
    );
    await expectLater(
      BundledServers(bundle: bundle).prepare(work),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('exceeds'),
        ),
      ),
    );
    expect(await work.list().toList(), isEmpty);
  });

  for (final defect in ['compression', 'size', 'hash']) {
    test('rejects $defect corruption before publishing any payload', () async {
      // 破坏最后一项，确保此前所有负载都已通过校验。
      if (defect == 'compression') {
        bundle.assets['${_prefix}x86.zlib'] = Uint8List.fromList([1, 2, 3]);
      } else {
        bundle.alterManifest((manifest) {
          final entry = (manifest['artifacts'] as List).last as Map;
          entry[defect == 'size' ? 'size' : 'sha256'] = defect == 'size'
              ? 1
              : '0' * 64;
        });
      }
      await expectLater(
        BundledServers(bundle: bundle).prepare(work),
        throwsA(anything),
      );
      expect(await work.list().toList(), isEmpty);
    });
  }

  for (final defect in [
    'path',
    'duplicate',
    'missing',
    'unknown',
    'version',
    'size',
    'oversize',
    'hash',
    'shape',
  ]) {
    test('rejects malformed manifest: $defect', () async {
      bundle.alterManifest((manifest) {
        final entries = manifest['artifacts'] as List;
        final first = entries.first as Map;
        switch (defect) {
          case 'path':
            first['file'] = '../../escaped.zlib';
          case 'duplicate':
            entries[1] = Map<String, dynamic>.from(first);
          case 'missing':
            entries.removeLast();
          case 'unknown':
            first['id'] = '../escaped';
          case 'version':
            manifest['version'] = 2;
          case 'size':
            first['size'] = 1.5;
          case 'oversize':
            first['size'] = 16 * 1024 * 1024 + 1;
          case 'hash':
            first['sha256'] = 'not-a-hash';
          case 'shape':
            entries[0] = 'scrcpy';
        }
      });
      await expectLater(
        BundledServers(bundle: bundle).prepare(work),
        throwsFormatException,
      );
      expect(await work.list().toList(), isEmpty);
      expect(bundle.loads, ['${_prefix}manifest.json']);
    });
  }

  test(
    'failed repair preserves existing cache without publishing bad bytes',
    () async {
      final servers = BundledServers(bundle: bundle);
      await servers.prepare(work);
      final cache = File('${work.path}/bundled_servers/x86');
      await cache.writeAsBytes([8, 9]);
      bundle.assets['${_prefix}x86.zlib'] = Uint8List.fromList([0]);
      await expectLater(servers.prepare(work), throwsA(anything));
      expect(await cache.readAsBytes(), [8, 9]);
      expect((await cache.parent.list().toList()).length, 6);
    },
  );

  test(
    'propagates publication failures and removes its private staging directory',
    () async {
      // 在缓存检查后制造冲突，以覆盖重命名失败及清理。
      final conflict = Directory('${work.path}/bundled_servers/x86');
      bundle.onLoad = (key) async {
        if (key == '${_prefix}x86.zlib') {
          await conflict.create(recursive: true);
        }
      };
      await expectLater(
        BundledServers(bundle: bundle).prepare(work),
        throwsA(isA<FileSystemException>()),
      );
      expect(await conflict.list().toList(), isEmpty);
      final entries = await conflict.parent.list().toList();
      expect(entries.length, 6);
      expect(entries.where((entry) => entry.path.contains('/.')), isEmpty);
    },
  );
}
