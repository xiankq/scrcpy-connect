import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/media/cache/app_media_cache.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/files/documents/delivery_journal.dart';

typedef Json = Map<String, dynamic>;
const source = <String, dynamic>{
  'sourceId': 'transfer-1',
  'localPath': '/private/cache/report.txt',
  'kind': 'file',
};
Json begin(String operation, [Json extra = const {}]) => {
  ...source,
  'operationId': operation,
  'name': 'report.txt',
  ...extra,
};
Json finish(String operation, Json result, [Json extra = const {}]) => {
  ...source,
  'operationId': operation,
  'result': result,
  ...extra,
};
Matcher code(String value) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  value,
);
Json record(Json receipt) => receipt['record'] as Json;
Json storedRecord(
  String operation, {
  String status = 'saved',
  Json? result,
  Json extra = const {},
}) => {
  ...source,
  'operationId': operation,
  'name': 'report.txt',
  'status': status,
  'result': status == 'pending' ? null : result ?? {'status': status},
  'updatedAt': 0,
  ...extra,
};
String key(Json row) =>
    jsonEncode([row['sourceId'], row['localPath'], row['kind']]);
Json ledger(List<Json> records, [List<String>? operations]) => {
  'version': 1,
  'records': {for (final row in records) key(row): row},
  'operations':
      operations ?? records.map((row) => row['operationId'] as String).toList(),
};

void main() {
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('delivery-journal-');
    file = File(p.join(root.path, 'deliveries.json'));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('真实日志 pending 提交与缓存清理共用 gate，核验和提交之间不会驱逐原件', () async {
    final gate = MediaCacheGate();
    final entered = Completer<void>(), proceed = Completer<void>();
    late final AppMediaCache cache;
    final journal = await DeliveryJournal.open(
      root,
      cacheGate: gate,
      validateSource: (path) async {
        await cache.validateDeliveryLocked(path);
        entered.complete();
        await proceed.future;
      },
    );
    cache = await AppMediaCache.open(
      root: root,
      gate: gate,
      protectedPaths: () => journal.protectedPaths,
    );
    final target = File(p.join(root.path, 'media', 'original'));
    await target.parent.create(recursive: true);
    await target.writeAsBytes([1, 2, 3]);
    final identity = <String, dynamic>{...source, 'localPath': target.path};
    final pending = journal.command('delivery.begin', {
      ...identity,
      'operationId': 'save',
      'name': 'original',
    });
    await entered.future;
    var cleared = false;
    final clearing = cache.clear().then((result) {
      cleared = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cleared, false);
    expect(await target.exists(), true);
    proceed.complete();
    await pending;
    expect((await clearing)['deletedBytes'], 0);
    expect(
      record(
        await (await DeliveryJournal.open(root))
            .command('delivery.get', identity),
      )['status'],
      'result_unknown',
    );
  });

  test('pending 重开可靠转 unknown，保留同次操作且重复重开不改写字节', () async {
    final journal = await DeliveryJournal.open(root);
    expect(await journal.command('delivery.get', source), {'record': null});
    expect(await file.exists(), isFalse);
    final pending = await journal.command('delivery.begin', begin('one'));
    expect(record(pending)['status'], 'pending');
    expect(await journal.protectedPaths, [source['localPath']]);
    final reopened = await DeliveryJournal.open(root);
    final receipt = await reopened.command('delivery.get', source);
    expect(record(receipt)['operationId'], 'one');
    expect(record(receipt)['result'], {
      'status': 'result_unknown',
      'partialDestinationPossible': true,
      'cacheRetained': true,
    });
    final bytes = await file.readAsBytes();
    final again = await DeliveryJournal.open(root);
    expect(await again.command('delivery.get', source), receipt);
    expect(await file.readAsBytes(), bytes);
    await expectLater(
      again.command('delivery.finish', finish('one', {'status': 'saved'})),
      throwsA(code('delivery_result_conflict')),
    );
  });

  test('已保存回执过滤授权信息，终态幂等且迟到及冲突回执被拒绝', () async {
    final journal = await DeliveryJournal.open(root);
    await journal.command('delivery.begin', begin('one'));
    final params = finish('one', {
      'status': 'saved',
      'name': 'actual.txt',
      'files': 1,
      'bytes': 24,
      'uri': 'content://secret',
      'created': [
        {'handle': 'secret'},
      ],
    });
    final saved = await journal.command('delivery.finish', params);
    expect(record(saved)['result'], {
      'status': 'saved',
      'name': 'actual.txt',
      'files': 1,
      'bytes': 24,
    });
    expect(await journal.protectedPaths, isEmpty);
    final bytes = await file.readAsBytes();
    expect(await journal.command('delivery.finish', params), saved);
    expect(await file.readAsBytes(), bytes);
    await expectLater(
      journal.command('delivery.finish', finish('old', {'status': 'saved'})),
      throwsA(code('delivery_operation_mismatch')),
    );
    await expectLater(
      journal.command('delivery.finish', finish('one', {'status': 'failed'})),
      throwsA(code('delivery_result_conflict')),
    );
    final reopened = await DeliveryJournal.open(root);
    expect(await reopened.command('delivery.get', source), saved);
    // 调用者不能通过回执对象绕过提交队列改变账本。
    (record(saved)['result'] as Json)['status'] = 'failed';
    expect(
      (record(await journal.command('delivery.get', source))['result']
          as Json)['status'],
      'saved',
    );
  });

  test('额外副本和未知重试分别要求确认精确旧操作，墓碑跨重开保留', () async {
    var journal = await DeliveryJournal.open(root);
    await journal.command('delivery.begin', begin('one'));
    await journal.command(
      'delivery.finish',
      finish('one', {'status': 'saved'}),
    );
    for (final authorization in [null, 'wrong']) {
      await expectLater(
        journal.command(
          'delivery.begin',
          begin('two', {'additionalCopyOfOperationId': authorization}),
        ),
        throwsA(code('delivery_saved')),
      );
    }
    await journal.command(
      'delivery.begin',
      begin('two', {'additionalCopyOfOperationId': 'one'}),
    );
    await journal.command(
      'delivery.finish',
      finish('two', {
        'status': 'resultUnknown',
        'partialDestinationPossible': false,
      }),
    );
    for (final extra in [
      <String, dynamic>{'additionalCopyOfOperationId': 'two'},
      {'reviewedOperationId': 'wrong'},
    ]) {
      await expectLater(
        journal.command('delivery.begin', begin('three', extra)),
        throwsA(code('delivery_review_required')),
      );
    }
    await journal.command(
      'delivery.begin',
      begin('three', {'reviewedOperationId': 'two'}),
    );
    await expectLater(
      journal.command('delivery.finish', finish('two', {'status': 'saved'})),
      throwsA(code('delivery_operation_mismatch')),
    );
    await journal.command(
      'delivery.finish',
      finish('three', {
        'status': 'cancelled',
        'partialDestinationPossible': false,
      }),
    );
    journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('one')),
      throwsA(code('delivery_operation_reused')),
    );
    await journal.command('delivery.begin', begin('four'));
    expect(await journal.protectedPaths, [source['localPath']]);
  });

  test('只有明确无部分目标的失败或取消可直接提交新操作', () async {
    final journal = await DeliveryJournal.open(root);
    await journal.command('delivery.begin', begin('one'));
    final receipt = await journal.command(
      'delivery.finish',
      finish('one', {'status': 'failed', 'name': ''}),
    );
    expect(
      (record(receipt)['result'] as Json)['partialDestinationPossible'],
      isTrue,
    );
    expect(await journal.protectedPaths, [source['localPath']]);
    await expectLater(
      journal.command('delivery.begin', begin('two')),
      throwsA(code('delivery_review_required')),
    );
    await journal.command(
      'delivery.begin',
      begin('two', {'reviewedOperationId': 'one'}),
    );
    await journal.command(
      'delivery.finish',
      finish('two', {'status': 'failed', 'partialDestinationPossible': false}),
    );
    expect(await journal.protectedPaths, isEmpty);
    await journal.command('delivery.begin', begin('three'));
  });

  test('并发准入只成功一个，路径、来源和种类独立，排队输入与输出均隔离', () async {
    final journal = await DeliveryJournal.open(root);
    Future<Object> attempt(String operation) async {
      try {
        return await journal.command('delivery.begin', begin(operation));
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait([attempt('one'), attempt('two')]);
    expect(results.whereType<Json>(), hasLength(1));
    expect(
      results.whereType<ApplicationCommandException>().single.code,
      'delivery_busy',
    );
    final alternate = begin('three', {'sourceId': 'other-device'});
    final pending = journal.command('delivery.begin', alternate);
    alternate['sourceId'] = 'mutated-after-submit';
    expect(record(await pending)['sourceId'], 'other-device');
    await journal.command(
      'delivery.begin',
      begin('four', {'sourceId': 'other-device', 'kind': 'directory'}),
    );
    await expectLater(
      journal.command(
        'delivery.finish',
        finish('three', {'status': 'saved'}, {'localPath': '/different'}),
      ),
      throwsA(code('delivery_not_found')),
    );
    expect(await journal.protectedPaths, hasLength(3));
  });

  test('UTF8 限额按字节且错误截断不切断字符，未知强制保护并删除授权字段', () async {
    final journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('one', {'sourceId': '界' * 86})),
      throwsA(code('invalid_argument')),
    );
    await expectLater(
      journal.command('delivery.begin', begin('one', {'name': '界' * 342})),
      throwsA(code('invalid_argument')),
    );
    await expectLater(
      journal.command(
        'delivery.begin',
        begin('one', {'name': 'bad\u0000name'}),
      ),
      throwsA(code('invalid_argument')),
    );
    await journal.command(
      'delivery.begin',
      begin('one', {'sourceId': '界' * 85}),
    );
    final receipt = await journal.command(
      'delivery.finish',
      finish(
        'one',
        {
          'status': 'resultUnknown',
          'partialDestinationPossible': false,
          'errors': List.generate(
            150,
            (_) => {
              'path': '界' * 2000,
              'code': '😀' * 100,
              'message': '界' * 2000,
              'handle': 'secret',
            },
          ),
        },
        {'sourceId': '界' * 85},
      ),
    );
    final result = record(receipt)['result'] as Json;
    expect(result['status'], 'result_unknown');
    expect(result['partialDestinationPossible'], isTrue);
    final errors = result['errors'] as List;
    expect(errors, hasLength(100));
    final error = errors.first as Json;
    expect(error.keys, unorderedEquals(['path', 'code', 'message']));
    expect(utf8.encode(error['path'] as String).length, 4095);
    expect(utf8.encode(error['code'] as String).length, 256);
    expect(utf8.encode(error['message'] as String).length, 4095);
    expect((error['message'] as String).contains('�'), isFalse);
    await DeliveryJournal.open(root);
  });

  test('参数和结果类型无效不会抹掉已准入记录', () async {
    final journal = await DeliveryJournal.open(root);
    for (final field in [
      'sourceId',
      'localPath',
      'kind',
      'operationId',
      'name',
    ]) {
      await expectLater(
        journal.command('delivery.begin', begin('one', {field: ''})),
        throwsA(code('invalid_argument')),
      );
    }
    await journal.command('delivery.begin', begin('one'));
    for (final result in [
      null,
      {'status': 'imported'},
      {'status': 'saved', 'files': -1},
      {'status': 'saved', 'bytes': 1.5},
      {'status': 'failed', 'partialDestinationPossible': 'false'},
      {
        'status': 'failed',
        'errors': ['bad'],
      },
    ]) {
      await expectLater(
        journal.command('delivery.finish', {
          ...source,
          'operationId': 'one',
          'result': result,
        }),
        throwsA(code('invalid_argument')),
      );
      expect(
        record(await journal.command('delivery.get', source))['status'],
        'pending',
      );
    }
  });

  test('v1 已保存、部分结果和墓碑兼容，损坏或较新格式原字节不变', () async {
    final row = storedRecord('one');
    final valid = ledger([row], ['one', 'retired-operation']);
    await file.writeAsString(jsonEncode(valid));
    var journal = await DeliveryJournal.open(root);
    expect(record(await journal.command('delivery.get', source)), row);
    final cases = <List<int>>[
      utf8.encode('{'),
      [0xff],
      List.filled(4 * 1024 * 1024 + 1, 32),
      utf8.encode(jsonEncode({...valid, 'version': 99})),
      utf8.encode(jsonEncode({...valid, 'extra': true})),
      utf8.encode(
        jsonEncode(
          ledger([
            {...row, 'unexpected': true},
          ]),
        ),
      ),
      utf8.encode(
        jsonEncode(
          ledger([
            {...row, 'updatedAt': -1},
          ]),
        ),
      ),
      utf8.encode(
        jsonEncode(
          ledger([
            {...row, 'result': null},
          ]),
        ),
      ),
      utf8.encode(
        jsonEncode(
          ledger([
            {
              ...row,
              'result': {'status': 'failed'},
            },
          ]),
        ),
      ),
      utf8.encode(jsonEncode(ledger([row], []))),
    ];
    for (final bytes in cases) {
      await file.writeAsBytes(bytes);
      await expectLater(
        DeliveryJournal.open(root),
        throwsA(code('delivery_storage_invalid')),
      );
      expect(await file.readAsBytes(), bytes);
    }
    await file.writeAsString(
      jsonEncode(
        ledger(
          [
            {
              ...row,
              'status': 'cancelled',
              'result': {
                'status': 'cancelled',
                'partialDestinationPossible': false,
              },
            },
          ],
          ['one', 'retired-operation'],
        ),
      ),
    );
    journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('retired-operation')),
      throwsA(code('delivery_operation_reused')),
    );
  });

  test('原子替换失败不提交内存、不消耗操作标识，修复后可重试并重开', () async {
    final journal = await DeliveryJournal.open(root);
    await Directory(file.path).create();
    await expectLater(
      journal.command('delivery.begin', begin('one')),
      throwsA(code('io_error')),
    );
    expect(await journal.command('delivery.get', source), {'record': null});
    expect(await root.list().length, 1);
    await Directory(file.path).delete();
    await journal.command('delivery.begin', begin('one'));
    final original = await file.readAsBytes();
    final preserved = File(p.join(root.path, 'preserved.json'));
    await file.rename(preserved.path);
    await Directory(file.path).create();
    await expectLater(
      journal.command('delivery.finish', finish('one', {'status': 'saved'})),
      throwsA(code('io_error')),
    );
    expect(
      record(await journal.command('delivery.get', source))['status'],
      'pending',
    );
    expect(await preserved.readAsBytes(), original);
    expect(await root.list().length, 2);
    await Directory(file.path).delete();
    await preserved.rename(file.path);
    final reopened = await DeliveryJournal.open(root);
    expect(
      record(await reopened.command('delivery.get', source))['status'],
      'result_unknown',
    );
    await expectLater(
      reopened.command('delivery.finish', finish('one', {'status': 'saved'})),
      throwsA(code('delivery_result_conflict')),
    );
  });

  test('记录和墓碑满额拒绝新保存，不淘汰旧结果，已有 pending 仍可完成', () async {
    final rows = List.generate(
      1024,
      (index) => storedRecord(
        'operation-$index',
        extra: {'sourceId': 'source-$index'},
      ),
    );
    rows[1] = storedRecord(
      'operation-1',
      status: 'pending',
      extra: {'sourceId': 'source-1'},
    );
    await file.writeAsString(jsonEncode(ledger(rows)));
    var journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('overflow')),
      throwsA(code('delivery_capacity')),
    );
    expect(
      record(
        await journal.command('delivery.get', {
          ...source,
          'sourceId': 'source-0',
        }),
      )['status'],
      'saved',
    );
    expect(
      record(
        await journal.command('delivery.get', {
          ...source,
          'sourceId': 'source-1',
        }),
      )['status'],
      'result_unknown',
    );
    await file.writeAsString(
      jsonEncode(
        ledger([], List.generate(16384, (index) => 'operation-$index')),
      ),
    );
    journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('overflow')),
      throwsA(code('delivery_capacity')),
    );
    await file.writeAsString(
      jsonEncode(
        ledger(
          [
            storedRecord(
              'old',
              status: 'cancelled',
              result: {
                'status': 'cancelled',
                'partialDestinationPossible': false,
              },
            ),
          ],
          ['old', ...List.generate(16382, (index) => 'operation-$index')],
        ),
      ),
    );
    journal = await DeliveryJournal.open(root);
    await journal.command('delivery.begin', begin('last-operation'));
    await journal.command(
      'delivery.finish',
      finish('last-operation', {'status': 'saved'}),
    );
    final reopened = await DeliveryJournal.open(root);
    expect(
      record(await reopened.command('delivery.get', source))['status'],
      'saved',
    );
  });

  test('大回执触及字节上限保留 pending，最小 unknown 可持久化并重开', () async {
    final journal = await DeliveryJournal.open(root);
    final errors = List.generate(
      100,
      (_) => {
        'path': '界' * 2000,
        'message': '界' * 2000,
        'code': 'write_failed',
      },
    );
    var full = false;
    for (var index = 0; index < 10; index++) {
      final identity = {'sourceId': 'source-$index'};
      await journal.command(
        'delivery.begin',
        begin('operation-$index', identity),
      );
      try {
        await journal.command(
          'delivery.finish',
          finish('operation-$index', {
            'status': 'partial',
            'errors': errors,
          }, identity),
        );
      } on ApplicationCommandException catch (error) {
        expect(error.code, 'delivery_capacity');
        expect(
          record(
            await journal.command('delivery.get', {...source, ...identity}),
          )['status'],
          'pending',
        );
        await journal.command(
          'delivery.finish',
          finish('operation-$index', {'status': 'result_unknown'}, identity),
        );
        final reopened = await DeliveryJournal.open(root);
        expect(
          record(
            await reopened.command('delivery.get', {...source, ...identity}),
          )['status'],
          'result_unknown',
        );
        full = true;
        break;
      }
    }
    expect(full, isTrue);
    expect(await file.length(), lessThanOrEqualTo(4 * 1024 * 1024));
  });

  test('pending 准入为恢复增加的 unknown 字段精确预留容量', () async {
    const maximum = 4 * 1024 * 1024;
    final safe = storedRecord(
      'old',
      status: 'failed',
      result: {'status': 'failed', 'partialDestinationPossible': false},
    );
    final pending = storedRecord(
      'new',
      status: 'pending',
      extra: {'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000},
    );
    final operations = <String>[
      'old',
      ...List.generate(16382, (index) => 't-$index'),
    ];
    // 让下一份 pending 的序列化内容可容纳，但剩余 128 字节不足其 256 字节恢复预留。
    var remaining =
        maximum -
        128 -
        utf8
            .encode(jsonEncode(ledger([pending], [...operations, 'new'])))
            .length;
    for (var index = 1; index < operations.length && remaining > 0; index++) {
      final available = 256 - operations[index].length;
      final amount = available < remaining ? available : remaining;
      operations[index] += 'x' * amount;
      remaining -= amount;
    }
    expect(remaining, 0);
    expect(
      utf8.encode(jsonEncode(ledger([pending], [...operations, 'new']))).length,
      maximum - 128,
    );
    final bytes = utf8.encode(jsonEncode(ledger([safe], operations)));
    expect(bytes.length, lessThan(maximum));
    await file.writeAsBytes(bytes);
    final journal = await DeliveryJournal.open(root);
    await expectLater(
      journal.command('delivery.begin', begin('new')),
      throwsA(code('delivery_capacity')),
    );
    expect(
      record(await journal.command('delivery.get', source))['operationId'],
      'old',
    );
    expect(await file.readAsBytes(), bytes);
  });
}
