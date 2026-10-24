import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late NativeAdbClient client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('adb-local-facts-');
    client = NativeAdbClient(await createNativeAdbApi(), '未使用的身份路径');
  });
  tearDown(() async {
    await client.close();
    await directory.delete(recursive: true);
  });

  test('真实 FRB 本机事实无需 ADB 连接，缺失类型码不依赖错误正文', () async {
    final path = p.join(directory.path, '不存在');
    await expectLater(
      client.services.localFileStat(utf8.encode(path)),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'not_found'),
      ),
    );
    await expectLater(
      client.services.localFileList(utf8.encode(path), limit: 10),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'not_found'),
      ),
    );
    expect(await client.devices(), isEmpty);
    expect(await Directory(directory.path).list().toList(), isEmpty);
  });

  test('真实本机目录保留合法替换字符、链接自身类型与有界批次', () async {
    final file = File(p.join(directory.path, '合法\ufffd名字'));
    await file.writeAsBytes([1, 2, 3], flush: true);
    final facts = await client.services.localFileList(
      utf8.encode(directory.path),
      limit: 10,
    );
    expect(facts.entries, hasLength(1));
    expect(facts.entries.single.name, utf8.encode('合法\ufffd名字'));
    final stamp = await client.services.localFileStat(utf8.encode(file.path));
    expect(stamp.mode & 0xf000, 0x8000);
    expect(stamp.size, 3);
    expect(stamp.nanosecondPrecision, isTrue);
    if (!Platform.isWindows) {
      final link = Link(p.join(directory.path, 'link'));
      await link.create(file.path);
      final linkStamp = await client.services.localFileStat(
        utf8.encode(link.path),
      );
      expect(linkStamp.mode & 0xf000, 0xa000);
    }
    final truncated = await client.services.localFileList(
      utf8.encode(directory.path),
      limit: 1,
    );
    expect(truncated.entries, hasLength(1));
    expect(truncated.truncated, !Platform.isWindows);
  });
}
