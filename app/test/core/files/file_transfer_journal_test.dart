import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_transfer_journal.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_record.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('transfer-journal-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('日志顺序登记不可变版本，重新打开保留原来源身份和最终进度', () async {
    final journal = FileTransferJournal(directory);
    await journal.load();
    const queued = FileTransferRecord(
      id: 'task',
      deviceId: 'device',
      batchId: 'batch',
      direction: .push,
      source: '/tmp/source',
      destination: '/sdcard/target',
      status: .queued,
      sourceStamp: FileStamp(mode: 0x8000, size: 9, modifiedSeconds: 5),
    );
    final first = journal.upsert(queued);
    final running = queued.copyWith(
      status: .running,
      generation: 1,
      transferred: 3,
    );
    final second = journal.upsert(running);
    final completed = running.copyWith(status: .completed, transferred: 9);
    final last = journal.upsert(completed);
    await Future.wait([first, second, last]);
    final rows = (await journal.file.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .where((row) => row['task'] != null)
        .toList();
    expect(rows.map((row) => (row['task'] as Map)['transferred']), [0, 3, 9]);
    final restored = (await FileTransferJournal(directory).load())['task']!;
    expect(restored, completed);
    expect(restored.sourceStamp, queued.sourceStamp);
    expect(queued.status, FileTransferStatus.queued);
    expect(queued.transferred, 0);
  });

  test('清空历史保留暂存路径与原件，重新打开日志恢复隐藏标记', () async {
    final original = File('${directory.path}/received.txt');
    await original.writeAsString('original contents');
    final journal = FileTransferJournal(directory);
    await journal.load();
    final complete = FileTransferRecord(
      id: 'done',
      deviceId: 'device',
      batchId: 'batch',
      direction: .pull,
      source: '/sdcard/original.txt',
      destination: original.path,
      destinationScope: .privateCache,
      status: .completed,
    );
    await journal.upsert(complete);
    await journal.upsert(complete.copyWith(id: 'active', status: .running));
    await journal.hideHistory(['done']);
    final restored = await FileTransferJournal(directory).load();
    expect(restored['done'], complete.copyWith(historyHidden: true));
    expect(restored['active']?.historyHidden, isFalse);
    expect(await original.readAsString(), 'original contents');
  });

  test('旧检查点在协议入口补齐默认值，迁移保留原文件且不改变来源身份', () async {
    final old = File('${directory.path}/transfers.json');
    final content = jsonEncode([
      {
        'id': 'legacy',
        'deviceId': 'device',
        'direction': 'push',
        'source': '/tmp/source',
        'destination': '/sdcard/target',
        'status': 'completed',
        'sourceStamp': {'mode': 0, 'size': 9, 'modifiedSeconds': 5},
      },
    ]);
    await old.writeAsString(content);
    final journal = FileTransferJournal(directory);
    final restored = (await journal.load())['legacy']!;
    expect(restored.batchId, 'legacy');
    expect(restored.kind, FileTransferKind.file);
    expect(restored.itemCount, 1);
    expect(
      restored.sourceStamp,
      const FileStamp(mode: 0x8000, size: 9, modifiedSeconds: 5),
    );
    expect(await old.readAsString(), content);
    expect((await FileTransferJournal(directory).load())['legacy'], restored);
  });

  test('零 mode 的真实特殊文件保留原身份，不套用旧普通文件的兼容规则', () async {
    final journal = FileTransferJournal(directory);
    await journal.load();
    const skipped = FileTransferRecord(
      id: 'special',
      deviceId: 'device',
      batchId: 'batch',
      direction: .push,
      source: '/tmp/source',
      destination: '/sdcard/target',
      status: .skipped,
      kind: .unsupported,
      sourceStamp: FileStamp(mode: 0, size: 0, modifiedSeconds: 5),
    );
    await journal.upsert(skipped);
    expect((await FileTransferJournal(directory).load())['special'], skipped);
  });

  test('无效旧记录在发布迁移文件前拒绝，原检查点可恢复且不写空日志', () async {
    final old = File('${directory.path}/transfers.json');
    final content = jsonEncode([
      {
        'id': 'legacy',
        'deviceId': 'device',
        'direction': 1,
        'source': '/tmp/source',
        'destination': '/sdcard/target',
      },
    ]);
    await old.writeAsString(content);
    final journal = FileTransferJournal(directory);
    await expectLater(
      journal.load(),
      throwsA(
        isA<FileFailure>().having(
          (e) => e.code,
          'code',
          'transfer_storage_corrupt',
        ),
      ),
    );
    expect(await old.readAsString(), content);
    expect(await journal.file.exists(), isFalse);
  });
}
