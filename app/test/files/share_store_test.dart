import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/files/sharing/share_store.dart';
import 'package:scrcpy_connect/files/sharing/share_store_format.dart';

const share = '11111111-1111-4111-8111-111111111111';
const second = '22222222-2222-4222-8222-222222222222';
const transfer = '33333333-3333-4333-8333-333333333333';
const leaseId = '44444444-4444-4444-8444-444444444444';
Matcher failure(String code) =>
    isA<FileFailure>().having((e) => e.code, 'code', code);

void main() {
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('share-store-test-');
  });
  tearDown(() async {
    await cache.delete(recursive: true);
  });
  Future<ShareStore> ready({ShareStoreCommit? commitFile}) async {
    final store = await ShareStore.open(
      cacheDirectory: cache,
      commitFile: commitFile,
    );
    await store.reserve(share, text: '文字');
    await File('${store.root.path}/$share/original').writeAsBytes([1, 2, 3]);
    await store.complete(share, const [
      SharedSourceFile(diskName: 'original', name: '照片📷', size: 3),
    ]);
    return store;
  }

  Map<String, Object?> request(ShareStore store) => {
    'deviceId': 'phone',
    'items': [
      {
        'source': '${store.root.path}/$share/original',
        'destination': '/sdcard/照片📷',
      },
    ],
    'conflict': 'ask',
  };

  test(
    'java properties migrates unicode, continuation and active lease in place',
    () async {
      final root = Directory('${cache.path}/incoming');
      await Directory('${root.path}/$share').create(recursive: true);
      await Directory('${root.path}/.leases').create();
      await File('${root.path}/$share/old.bin').writeAsBytes([5, 6]);
      await File('${root.path}/$share/.share').writeAsString(
        'count=1\ncreated=123\nvisible=true\nstatus=ready\ntext=hello\\\n  world\nmime=text/plain\nfile.0.disk=old.bin\nfile.0.name=\\uD83D\\uDCF7\\u4E2D\n',
      );
      await File('${root.path}/.leases/$leaseId')
          .writeAsString('share=$share\ntransfer=$transfer\n');
      final store = await ShareStore.open(cacheDirectory: cache);
      final row = (await store.pending())['shares'].single;
      expect(row['text'], 'helloworld');
      expect(row['files'].single, {
        'name': '📷中',
        'size': 2,
        'localPath': '${root.path}/$share/old.bin',
      });
      expect(
        jsonDecode(
          await File('${root.path}/$share/.share').readAsString(),
        )['version'],
        2,
      );
      expect((await store.sources())['leases'].single['transferId'], transfer);
      await store.command('sharing.consume', {'shareId': share});
      expect(await File('${root.path}/$share/old.bin').exists(), true);
    },
  );

  test(
    'publication marker survives restart as unknown and never replays',
    () async {
      final store = await ready();
      final input = request(store);
      expect(await store.begin(share, input), null);
      final reopened = await ShareStore.open(cacheDirectory: cache);
      expect(
        (await reopened.sources())['leases'].single['publication'],
        'unknown',
      );
      await expectLater(
        reopened.begin(share, input),
        throwsA(failure('share_submission_unknown')),
      );
      await expectLater(
        reopened.begin(share, {...input, 'deviceId': 'other'}),
        throwsA(failure('share_submission_mismatch')),
      );
      await expectLater(
        reopened.finish(share, null, definitelyUnpublished: true),
        throwsA(failure('share_submission_unknown')),
      );
    },
  );

  test('definitely unpublished retry and compact durable receipt protect exact submission', () async {
    final store = await ready();
    final input = request(store);
    await store.begin(share, input);
    await store.finish(share, null, definitelyUnpublished: true);
    expect(await store.begin(share, input), null);
    await store.finish(share, {
      'batchId': transfer,
      'transferIds': [second],
      'status': 'submitted',
      'hugeSnapshot': List.filled(20000, 'x'),
    });
    final reopened = await ShareStore.open(cacheDirectory: cache);
    final receipt = await reopened.begin(share, input);
    expect(receipt, {
      'batchId': transfer,
      'transferIds': [second],
      'status': 'submitted',
    });
    expect(
      (await Directory('${store.root.path}/.leases').list().single as File)
          .lengthSync(),
      lessThan(16384),
    );
  });

  test('only full durable positive completion releases sources; failed and incomplete retain', () async {
    final store = await ready();
    await store.begin(share, request(store), transferId: transfer);
    await store.command('sharing.consume', {'shareId': share});
    final path = '${store.root.path}/$share/original';
    Map<String, Object?> snapshot(String status, {bool complete = true}) => {
      'complete': complete,
      'transfers': [
        {
          'id': transfer,
          'status': status,
          'sources': [path],
        },
      ],
    };
    await store.reconcile(snapshot('failed'));
    await store.reconcile(snapshot('completed', complete: false));
    expect(await File(path).exists(), true);
    await expectLater(
      store.command('sharing.release', {
        'leaseId': (await store.sources())['leases'].single['leaseId'],
      }),
      throwsA(failure('share_lease_in_use')),
    );
    await store.reconcile(snapshot('completed'));
    expect(await File(path).exists(), false);
    expect((await store.sources())['leases'], isEmpty);
  });

  test(
    'source coverage never claims a newly arrived share was checked',
    () async {
      final store = await ready();
      await store.begin(share, request(store));
      await store.finish(share, {'batchId': transfer, 'status': 'queued'});
      await store.command('sharing.consume', {'shareId': share});
      final covered = await store.sourcePaths;
      final original = covered.single;

      await store.reserve(second);
      final late = File('${store.root.path}/$second/late');
      await late.writeAsBytes([4]);
      await store.complete(second, const [
        SharedSourceFile(diskName: 'late', name: 'late', size: 1),
      ]);
      await store.begin(second, {
        'items': [
          {'source': late.path, 'destination': '/sdcard/late'},
        ],
      });
      await store.finish(second, {'batchId': leaseId, 'status': 'queued'});
      await store.command('sharing.consume', {'shareId': second});

      final invalid = await store.reconcile({
        'complete': true,
        'transfers': [
          {
            'id': leaseId,
            'status': 'completed',
            'sources': [late.path],
          },
        ],
      }, coveredSources: covered);
      expect(invalid['reason'], 'invalid_snapshot');
      expect(await File(original).exists(), isTrue);
      expect(await late.exists(), isTrue);

      final result = await store.reconcile({
        'complete': true,
        'transfers': [
          {
            'id': transfer,
            'status': 'completed',
            'sources': [original],
          },
        ],
      }, coveredSources: covered);
      expect(result['snapshotComplete'], isFalse);
      expect(result['reason'], 'source_coverage_changed');
      expect(await File(original).exists(), isFalse);
      expect(await late.exists(), isTrue);
      expect((await store.sources())['leases'], hasLength(1));
    },
  );

  test('overflow, empty references and additional noncompleted consumers forbid reclamation', () async {
    final store = await ready();
    await store.begin(share, request(store), transferId: transfer);
    await store.command('sharing.consume', {'shareId': share});
    final path = '${store.root.path}/$share/original';
    final result = await store.reconcile({
      'complete': true,
      'transfers': List.generate(
        1025,
        (i) => {
          'id': '$i',
          'status': 'completed',
          'sources': [path],
        },
      ),
    });
    expect(result['reason'], 'reference_limit');
    await store.reconcile({
      'complete': true,
      'transfers': [
        {
          'id': transfer,
          'status': 'completed',
          'sources': [path],
        },
        {
          'id': second,
          'status': 'failed',
          'sources': [path],
        },
      ],
    });
    expect(await File(path).exists(), true);
    await store.reconcile({
      'complete': true,
      'transfers': [
        {
          'id': transfer,
          'status': 'completed',
          'sources': [path],
        },
        {'id': second, 'status': 'completed', 'sources': <String>[]},
      ],
    });
    expect(await File(path).exists(), true);
  });

  test(
    'unknown newer and corrupt journals are preserved and block new admission',
    () async {
      final root = Directory('${cache.path}/incoming');
      await Directory('${root.path}/$share').create(recursive: true);
      final journal = File('${root.path}/$share/.share');
      await journal.writeAsString('{"version":999,"id":"$share"}');
      final original = await journal.readAsBytes();
      final store = await ShareStore.open(cacheDirectory: cache);
      await expectLater(
        store.reserve(second),
        throwsA(failure('share_cache_busy')),
      );
      expect(await journal.readAsBytes(), original);
      expect(
        (await store.reconcile({
          'complete': true,
          'transfers': [],
        }))['needsReview'],
        true,
      );
    },
  );

  test('symbolic roots, batch file links and lease directory links never escape scope', () async {
    final external = await Directory.systemTemp.createTemp('share-external-');
    try {
      await Link('${cache.path}/incoming').create(external.path);
      await expectLater(
        ShareStore.open(cacheDirectory: cache),
        throwsA(failure('share_source_invalid')),
      );
      await Link('${cache.path}/incoming').delete();
      final store = await ShareStore.open(cacheDirectory: cache);
      await store.reserve(share);
      final outside = File('${external.path}/keep');
      await outside.writeAsString('keep');
      await Link('${store.root.path}/$share/escape').create(outside.path);
      await expectLater(
        store.complete(share, const [
          SharedSourceFile(diskName: 'escape', name: 'escape', size: 4),
        ]),
        throwsA(failure('share_source_invalid')),
      );
      await store.fail(share, 'cancelled');
      expect(await outside.readAsString(), 'keep');
      await Directory('${store.root.path}/.leases').delete();
      await Link('${store.root.path}/.leases').create(external.path);
      await expectLater(
        ShareStore.open(cacheDirectory: cache),
        throwsA(failure('share_source_invalid')),
      );
      expect(await outside.readAsString(), 'keep');
    } finally {
      await external.delete(recursive: true);
    }
  });

  test('failed commit freezes all later writes without overwriting the old journal', () async {
    var failCommit = false;
    final store = await ready(
      commitFile: (temporary, destination) async {
        if (failCommit) {
          throw FileSystemException(
            'controlled rename failure',
            destination.path,
          );
        }
        await temporary.rename(destination.path);
      },
    );
    final journal = File('${store.root.path}/$share/.share');
    final original = await journal.readAsBytes();
    failCommit = true;
    await expectLater(
      store.command('sharing.consume', {'shareId': share}),
      throwsA(failure('share_storage_unknown')),
    );
    expect(await journal.readAsBytes(), original);
    expect((await store.pending())['shares'], hasLength(1));
    await expectLater(
      store.reserve(second),
      throwsA(failure('share_storage_unknown')),
    );
    final reopened = await ShareStore.open(cacheDirectory: cache);
    await reopened.command('sharing.consume', {'shareId': share});
    expect(await journal.exists(), false);
  });

  test(
    'lost commit receipt with verified bytes is recognized as committed',
    () async {
      var loseReceipt = false;
      final store = await ready(
        commitFile: (temporary, destination) async {
          await temporary.rename(destination.path);
          if (loseReceipt &&
              jsonDecode(await destination.readAsString())['publication'] ==
                  'publishing') {
            throw FileSystemException('receipt lost', destination.path);
          }
        },
      );
      loseReceipt = true;
      await store.begin(share, request(store));
      expect(
        (await store.sources())['leases'].single['publication'],
        'publishing',
      );
      await expectLater(
        store.begin(share, request(store)),
        throwsA(failure('share_submission_unknown')),
      );
    },
  );

  test('completed rename with unobservable receipt fences writes until explicit reopen', () async {
    var loseReceipt = false;
    File? committed;
    File? saved;
    final store = await ready(
      commitFile: (temporary, destination) async {
        await temporary.rename(destination.path);
        if (loseReceipt &&
            jsonDecode(await destination.readAsString())['publication'] ==
                'publishing') {
          committed = destination;
          saved = await destination.rename('${destination.path}.unobservable');
          await Directory(destination.path).create();
          throw FileSystemException(
            'receipt and verification unavailable',
            destination.path,
          );
        }
      },
    );
    loseReceipt = true;
    await expectLater(
      store.begin(share, request(store)),
      throwsA(failure('share_storage_unknown')),
    );
    await expectLater(
      store.reserve(second),
      throwsA(failure('share_storage_unknown')),
    );
    expect((await store.sources())['leases'].single['publication'], null);
    // 故障解除后恢复已经提交的真实新字节，旧实例仍不得继续覆盖它。
    await Directory(committed!.path).delete();
    await saved!.rename(committed!.path);
    await expectLater(
      store.begin(share, request(store)),
      throwsA(failure('share_storage_unknown')),
    );
    final reopened = await ShareStore.open(cacheDirectory: cache);
    expect(
      (await reopened.sources())['leases'].single['publication'],
      'unknown',
    );
    await expectLater(
      reopened.begin(share, request(reopened)),
      throwsA(failure('share_submission_unknown')),
    );
  });

  test('reopen marks drained interrupted import failed and removes only its private fragments', () async {
    final store = await ShareStore.open(cacheDirectory: cache);
    await store.reserve(share);
    final part = File('${store.root.path}/$share/partial');
    await part.writeAsString('partial');
    final reopened = await ShareStore.open(cacheDirectory: cache);
    expect((await reopened.pending())['shares'].single['status'], 'error');
    expect(await part.exists(), false);
  });

  test('consume drains outside the store queue and does not deadlock a worker finally', () async {
    late ShareStore store;
    final started = Completer<void>(), release = Completer<void>();
    store = await ShareStore.open(
      cacheDirectory: cache,
      beforeRemove: (id) async {
        started.complete();
        await release.future;
        await store.fail(id, 'drained');
      },
    );
    await store.reserve(share);
    final consuming = store.command('sharing.consume', {'shareId': share});
    await started.future;
    expect((await store.pending())['shares'].single['status'], 'importing');
    release.complete();
    await consuming;
    expect((await store.pending())['shares'], isEmpty);
  });

  test('active copies cannot be deleted without a drain callback', () async {
    final store = await ShareStore.open(cacheDirectory: cache);
    await store.reserve(share);
    await expectLater(
      store.command('sharing.cancel', {'shareId': share}),
      throwsA(failure('share_import_active')),
    );
    expect((await store.existing(share))!['status'], 'starting');
  });

  test(
    'limits use real file sizes and cannot publish a partially imported batch',
    () async {
      final store = await ShareStore.open(
        cacheDirectory: cache,
        limits: const ShareLimits(fileBytes: 3, batchBytes: 4, totalBytes: 5),
      );
      await store.reserve(share);
      expect(await store.availableBytes(share), 4);
      await File('${store.root.path}/$share/a').writeAsBytes([1, 2, 3]);
      await File('${store.root.path}/$share/b').writeAsBytes([4, 5]);
      await expectLater(
        store.complete(share, const [
          SharedSourceFile(diskName: 'a', name: 'a', size: 3),
          SharedSourceFile(diskName: 'b', name: 'b', size: 2),
        ]),
        throwsA(failure('share_byte_limit')),
      );
      await expectLater(
        store.begin(share, {
          'items': [
            {'source': '${store.root.path}/$share/a'},
          ],
        }),
        throwsA(failure('share_source_invalid')),
      );
    },
  );

  test('fingerprint is structural, ordered by UTF8 and follows serde_json numeric layout', () {
    // 固定输出来自当前 Rust serde_json/sha2 与旧 policy.rs 的同一编码算法。
    expect(
      shareRequestFingerprint({
        'b': [null, true, 1],
        'a': '中📷',
      }),
      'sha256:518b21de9d0ca0b6d0ccb24bd43b1484b0c26e45ae7d0bbc3efb00efab4f991a',
    );
    expect(
      shareRequestFingerprint({'\ue000': 1, '😀': 2}),
      'sha256:1468f76bcb439ba653bd285d7a74f1f10cb653487f0960ba3863f4dd7946f285',
    );
    expect(
      shareRequestFingerprint([1e-6, 1e16, -0.0]),
      'sha256:e1af7901cfb32a1ac882ba0f27068319c63749dc26e057f50d145df5839d11e6',
    );
    expect(
      shareRequestFingerprint({
        'b': [null, true, 1],
        'a': '中📷',
      }),
      shareRequestFingerprint({
        'a': '中📷',
        'b': [null, true, 1],
      }),
    );
    expect(shareRequestFingerprint([1]), isNot(shareRequestFingerprint([1.0])));
    expect(
      shareRequestFingerprint({'a': 1}),
      isNot(shareRequestFingerprint({'a': '1'})),
    );
    expect(shareRequestFingerprint([1e-6, 1e16, -0.0]), startsWith('sha256:'));
    expect(readShareProperties(latin1.encode('a\\=b: c\\t\\u4e2d\n')), {
      'a=b': 'c\t中',
    });
    expect(
      () => readShareProperties(latin1.encode('broken=\\uD800\n')),
      throwsFormatException,
    );
  });
}
