import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_files/device_files.dart';
import 'package:device_protocol/device_protocol.dart';

class Fixture {
  final calls = <(String, DocumentsJson)>[];
  final nodes = <String, DocumentsJson>{};
  final children = <String, List<String>>{};
  final local = <String, DocumentsJson>{};
  List<String> selected = [];
  String choice = 'keepBoth';
  bool mutateSource = false, loseCreate = false, failClose = false;
  Completer<DocumentsJson>? picker;
  DocumentsJson node(
    String id,
    String name, {
    bool directory = false,
    int size = 3,
  }) {
    return nodes[id] = {
      'handle': id,
      'id': id,
      'authority': 'fixture',
      'uri': 'content://fixture/$id',
      'name': name,
      'directory': directory,
      'virtual': false,
      'canCreate': directory,
      'canWrite': !directory,
      'size': directory ? null : size,
      'modified': 1,
    };
  }

  late final coordinator = DocumentsCoordinator(core: core, platform: platform);
  Future<DocumentsJson> platform(String command, DocumentsJson params) async {
    calls.add((command, params));
    final id = params['handle'];
    switch (command) {
      case 'documents.platform.environment':
        return {
          'cacheDirectory': '/cache',
          'screenshotsDirectory': '/files/screenshots',
        };
      case 'documents.platform.picker':
        return picker?.future ??
            {
              'status': 'selected',
              'documents': [
                for (final id in selected)
                  {'handle': id, 'uri': 'content://fixture/$id'},
              ],
            };
      case 'documents.platform.metadata':
        return {...nodes[id]!};
      case 'documents.platform.children':
        return {
          'documents': [
            for (final child in children[id] ?? <String>[]) {...nodes[child]!},
          ],
          'hasMore': false,
        };
      case 'documents.platform.openFd':
        return {'fd': 44, 'fdLeaseId': 'lease-$id'};
      case 'documents.platform.releaseFd':
        if (failClose) {
          throw const InteropException(
            'close_failed',
            'provider refused close',
          );
        }
        return {'released': true};
      case 'documents.platform.cancel':
        picker?.complete({'status': 'cancelled'});
        picker = null;
        return {'cancelled': true};
      case 'documents.platform.conflict':
        return {'choice': choice};
      case 'documents.platform.create':
        if (loseCreate) throw const InteropException('binder_lost', 'lost');
        final next = 'created-${nodes.length}';
        final fresh = node(
          next,
          params['name'] as String,
          directory: params['mime'] == 'vnd.android.document/directory',
          size: 0,
        );
        children.putIfAbsent(id as String, () => []).add(next);
        return {...fresh};
      default:
        return {};
    }
  }

  Future<DocumentsJson> core(String command, DocumentsJson params) async {
    calls.add((command, params));
    switch (command) {
      case 'document.limits':
        return {
          'maxEntries': 10000,
          'maxDepth': 64,
          'maxPathBytes': 16777216,
          'maxBytes': 8589934592,
          'timeoutMillis': 600000,
          'reserveBytes': 33554432,
          'maxErrors': 1000,
          'maxSelected': 1000,
        };
      case 'document.mkdir':
        local[params['path'] as String] = {'kind': 'directory'};
        return {'created': true};
      case 'document.localStat':
        return {'freeBytes': 1000000000, ...?local[params['path']]};
      case 'document.localChildren':
        return {
          'entries': <DocumentsJson>[],
          'identity': local[params['path']],
        };
      case 'document.copy':
        if (mutateSource) nodes[selected.single]!['modified'] = 2;
        if (params.containsKey('targetFd')) {
          final handle = calls
              .lastWhere((call) => call.$1 == 'documents.platform.openFd')
              .$2['handle'];
          nodes[handle]!['size'] = 3;
        }
        if (params.containsKey('targetPath')) {
          local[params['targetPath'] as String] = {'kind': 'file', 'size': 3};
        }
        return {
          'bytes': 3,
          'identity': {'kind': 'file', 'size': 3},
        };
      case 'document.commit':
        local[params['path'] as String] = local.remove(params['partPath'])!;
        return {'committed': true};
      case 'document.remove':
        local.remove(params['path']);
        return {'removed': true};
      default:
        return {};
    }
  }
}

void main() {
  for (final applyToRemaining in [false, true]) {
    testWidgets(
      'skip applies ${applyToRemaining ? 'through this save only' : 'to one conflict only'}',
      (tester) async {
        final f = Fixture()..selected = ['parent'];
        f.node('parent', 'Target', directory: true);
        f.local['/cache/source'] = {'kind': 'directory'};
        final events = <DocumentsJson>[];
        final coordinator = DocumentsCoordinator(
          core: (command, params) async {
            if (command == 'document.localChildren' &&
                params['path'] == '/cache/source') {
              return {
                'identity': {'kind': 'directory'},
                'entries': [
                  for (final name in ['one', 'two'])
                    {
                      'name': name,
                      'path': '/cache/source/$name',
                      'identity': {'kind': 'directory'},
                    },
                ],
              };
            }
            return f.core(command, params);
          },
          platform: (command, params) async {
            final result = await f.platform(command, params);
            if (command == 'documents.platform.create' &&
                params['name'] == 'Tree') {
              // A provider-side writer creates same-name children after our new
              // root appears. Both are external filesystem conflicts.
              for (final name in ['one', 'two']) {
                f.node(name, name, directory: true);
              }
              f.children[result['handle'] as String] = ['one', 'two'];
            }
            return result;
          },
          onConflictChanged: events.add,
        );
        f.local['/cache/source/one'] = {'kind': 'directory'};
        f.local['/cache/source/two'] = {'kind': 'directory'};
        final job = coordinator.request('documents.export', {
          'operationId': 'batch',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        });
        await tester.pump();
        final first = events.last['pending'] as DocumentsJson;
        expect(first['name'], 'one');
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'batch',
          'conflictId': first['conflictId'],
          'choice': 'skip',
          'applyToRemaining': applyToRemaining,
        });
        await tester.pump();
        if (!applyToRemaining) {
          final second = events.last['pending'] as DocumentsJson;
          expect(second['name'], 'two');
          expect(
            await coordinator.request('documents.conflict.resolve', {
              'operationId': 'batch',
              'conflictId': first['conflictId'],
              'choice': 'cancel',
            }),
            {'resolved': false},
          );
          await coordinator.request('documents.conflict.resolve', {
            'operationId': 'batch',
            'conflictId': second['conflictId'],
            'choice': 'skip',
          });
        }
        final result = await job;
        expect(result['status'], 'partial');
        expect(result['skipped'], 2);
        expect(
          events.where((event) => event['pending'] != null),
          hasLength(applyToRemaining ? 1 : 2),
        );
        final next = coordinator.request('documents.export', {
          'operationId': 'next-batch',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        });
        await tester.pump();
        expect(
          (events.last['pending'] as DocumentsJson)['operationId'],
          'next-batch',
        );
        await coordinator.request('documents.cancel', {
          'operationId': 'next-batch',
        });
        expect((await next)['status'], 'cancelled');
        await coordinator.dispose();
      },
    );
  }

  testWidgets(
    'an unanswered shared conflict expires and cannot hold the next save',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final coordinator = DocumentsCoordinator(
        core: (command, params) async {
          final response = await f.core(command, params);
          return command == 'document.limits'
              ? {...response, 'timeoutMillis': 20}
              : response;
        },
        platform: f.platform,
      );
      final job = coordinator.request('documents.export', {
        'operationId': 'timeout-conflict',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await tester.pump();
      final pending =
          (await coordinator.request('documents.conflict.get', {
                'operationId': 'timeout-conflict',
              }))['pending']
              as DocumentsJson;
      await expectLater(
        coordinator.request('documents.conflict.resolve', {
          ...pending,
          'choice': 'replace',
        }),
        throwsA(isA<InteropException>()),
      );
      await tester.pump(const Duration(milliseconds: 21));
      final result = await job;
      expect(result['status'], 'partial');
      expect(
        (result['errors'] as List).single,
        containsPair('code', 'timeout'),
      );
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'timeout-conflict',
        }))['pending'],
        isNull,
      );
      expect(
        await coordinator.request('documents.conflict.resolve', {
          ...pending,
          'choice': 'keepBoth',
        }),
        {'resolved': false},
      );
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.create'),
        isEmpty,
      );
      f.children['parent'] = [];
      expect(
        (await coordinator.request('documents.export', {
          'operationId': 'healthy-next',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        }))['status'],
        'saved',
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'conflict cancellation clears its event and stale decisions cannot resolve another operation',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final events = <DocumentsJson>[];
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: f.platform,
        onConflictChanged: events.add,
      );
      Future<DocumentsJson> start(String id) =>
          coordinator.request('documents.export', {
            'operationId': id,
            'localPath': '/cache/source',
            'kind': 'directory',
            'name': 'Tree',
          });
      final oldJob = start('old-operation');
      await tester.pump();
      final oldPending = events.single['pending'] as DocumentsJson;
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'other-device-operation',
        }))['pending'],
        isNull,
      );
      await coordinator.request('documents.cancel', {
        'operationId': 'old-operation',
      });
      expect((await oldJob)['status'], 'cancelled');
      expect(events.last, {'operationId': 'old-operation', 'pending': null});
      final newJob = start('new-operation');
      await tester.pump();
      final current = events.last['pending'] as DocumentsJson;
      expect(
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'old-operation',
          'conflictId': oldPending['conflictId'],
          'choice': 'keepBoth',
        }),
        {'resolved': false},
      );
      expect(
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'new-operation',
          'conflictId': oldPending['conflictId'],
          'choice': 'cancel',
        }),
        {'resolved': false},
      );
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'new-operation',
          'conflictId': current['conflictId'],
        }))['pending'],
        current,
      );
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        isEmpty,
      );
      await coordinator.request('documents.conflict.resolve', {
        'operationId': 'new-operation',
        'conflictId': current['conflictId'],
        'choice': 'cancel',
      });
      expect((await newJob)['status'], 'cancelled');
      await coordinator.dispose();
    },
  );
  test(
    'a rejected source before the picker is failed without a partial save',
    () async {
      final f = Fixture();
      final coordinator = DocumentsCoordinator(
        platform: f.platform,
        core: (command, params) async {
          if (command == 'document.localStat') {
            throw const InteropException('source_changed', '原文件已变化');
          }
          return f.core(command, params);
        },
      );
      final result = await coordinator.request('documents.export', {
        'operationId': 'preflight-rejected',
        'localPath': '/cache/outgoing/original',
        'name': 'original',
        'kind': 'file',
      });
      expect(result['status'], 'failed');
      expect(result['files'], 0);
      expect(result['bytes'], 0);
      expect(result['partialDestinationPossible'], false);
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.picker'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );
  testWidgets(
    'a never responding metadata query times out and releases the operation',
    (tester) async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      final pending = Completer<DocumentsJson>();
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: (command, params) {
          if (command == 'documents.platform.metadata') return pending.future;
          return f.platform(command, params);
        },
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importDirectory', {
            'operationId': 'metadata-timeout',
          })
          .then((value) {
            result = value;
          });
      await tester.pump();
      await tester.pump(const Duration(seconds: 121));
      await tester.pump();
      expect(
        result,
        isNotNull,
        reason: 'Metadata must use the bounded platform wait.',
      );
      expect(result!['status'], 'partial');
      expect(
        (result!['errors'] as List<Object?>).single,
        containsPair('code', 'timeout'),
      );
      await job;
      f.selected = [];
      final next = await coordinator.request('documents.importFiles', {
        'operationId': 'after-timeout',
      });
      expect(next['status'], 'partial');
      expect(
        (next['errors'] as List<Object?>).single,
        containsPair('code', 'invalid_uri'),
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'shared cancellation releases a picker without waiting for its native reply',
    (tester) async {
      final f = Fixture();
      f.node('late', 'late.txt');
      final first = Completer<DocumentsJson>();
      final second = Completer<DocumentsJson>();
      var picks = 0;
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: (command, params) {
          if (command == 'documents.platform.picker') {
            return ++picks == 1 ? first.future : second.future;
          }
          return f.platform(command, params);
        },
      );
      DocumentsJson? firstResult, secondResult;
      final oldJob = coordinator
          .request('documents.importFiles', {'operationId': 'old'})
          .then((value) {
            firstResult = value;
          });
      await tester.pump();
      await coordinator.request('documents.cancel', {'operationId': 'old'});
      await tester.pump();
      expect(firstResult?['status'], 'cancelled');
      await oldJob;
      final newJob = coordinator
          .request('documents.importFiles', {'operationId': 'new'})
          .then((value) {
            secondResult = value;
          });
      await tester.pump();
      first.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'late'},
        ],
      });
      await tester.pump(const Duration(seconds: 121));
      expect(secondResult, isNull);
      expect(f.calls.where((call) => call.$1 == 'document.copy'), isEmpty);
      expect(
        f.calls
            .where((call) => call.$1 == 'document.cancel')
            .map((call) => call.$2['operationId']),
        ['old'],
      );
      await coordinator.request('documents.cancel', {'operationId': 'new'});
      await tester.pump();
      await newJob;
      expect(secondResult?['status'], 'cancelled');
      second.completeError(
        const InteropException('late_provider', 'late provider failure'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await coordinator.dispose();
    },
  );

  testWidgets(
    'metadata cancellation ignores its late provider error and cannot affect the next selection',
    (tester) async {
      final f = Fixture()..selected = ['file'];
      f.node('file', 'data.txt');
      final pending = Completer<DocumentsJson>();
      var blocked = true;
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: (command, params) {
          if (blocked && command == 'documents.platform.metadata') {
            return pending.future;
          }
          return f.platform(command, params);
        },
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importFiles', {'operationId': 'cancel-meta'})
          .then((value) {
            result = value;
          });
      await tester.pump();
      await coordinator.request('documents.cancel', {
        'operationId': 'cancel-meta',
      });
      await tester.pump();
      expect(result?['status'], 'cancelled');
      await job;
      blocked = false;
      final next = await coordinator.request('documents.importFiles', {
        'operationId': 'healthy',
      });
      expect(next['status'], 'imported');
      pending.completeError(
        const InteropException('late_metadata', 'late response'),
      );
      await tester.pump(const Duration(seconds: 121));
      expect(tester.takeException(), isNull);
      expect(
        f.calls
            .where((call) => call.$1 == 'document.cancel')
            .map((call) => call.$2['operationId']),
        ['cancel-meta'],
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'disposal releases a picker that never acknowledges cancellation',
    (tester) async {
      final f = Fixture();
      final pending = Completer<DocumentsJson>();
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: (command, params) => command == 'documents.platform.picker'
            ? pending.future
            : f.platform(command, params),
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importFiles', {'operationId': 'disposed'})
          .then((value) {
            result = value;
          });
      await tester.pump();
      await coordinator.dispose();
      await tester.pump();
      expect(result?['status'], 'cancelled');
      await job;
      pending.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'late'},
        ],
      });
      await tester.pump();
      expect(f.calls.where((call) => call.$1 == 'document.copy'), isEmpty);
    },
  );

  test(
    'a completed save confirms provider success before reporting saved',
    () async {
      final f = Fixture()..selected = ['file'];
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final coordinator = DocumentsCoordinator(
        core: f.core,
        platform: (command, params) {
          if (command == 'documents.platform.releaseFd' &&
              params['outcome'] != 'success') {
            throw const InteropException(
              'provider_incomplete',
              'provider did not receive successful completion',
            );
          }
          return f.platform(command, params);
        },
      );
      final result = await coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'saved');
      expect(result['files'], 1);
      expect(result['uri'], 'content://fixture/file');
      expect(result['bytes'], 3);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.releaseFd'),
        hasLength(1),
      );
      expect(
        f.calls
            .singleWhere((c) => c.$1 == 'document.copy')
            .$2['sourceIdentity'],
        containsPair('size', 3),
      );
      await coordinator.dispose();
    },
  );

  test(
    'a failed write aborts its provider lease and preserves the write error',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final coordinator = DocumentsCoordinator(
        core: (command, params) async {
          if (command == 'document.copy') {
            f.calls.add((command, params));
            f.nodes['file']!['size'] = 1;
            throw const InteropException('write_failed', 'provider stopped', {
              'bytesCopied': 1,
              'partialDestinationPossible': true,
            });
          }
          return f.core(command, params);
        },
        platform: f.platform,
      );
      final result = await coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'partial');
      expect(result['files'], 0);
      expect(result['bytes'], 1);
      expect(result['partialDestinationPossible'], isTrue);
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'write_failed'),
      );
      expect(
        f.calls
            .singleWhere((call) => call.$1 == 'documents.platform.releaseFd')
            .$2['outcome'],
        'abort',
      );
      expect(f.calls.where((call) => call.$1 == 'document.copy'), hasLength(1));
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.delete'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );

  test(
    'cancelling a write retains possible output without reporting it saved',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final copying = Completer<void>();
      final copied = Completer<DocumentsJson>();
      final coordinator = DocumentsCoordinator(
        core: (command, params) {
          if (command == 'document.copy') {
            f.calls.add((command, params));
            copying.complete();
            return copied.future;
          }
          return f.core(command, params);
        },
        platform: f.platform,
      );
      final job = coordinator.request('documents.export', {
        'operationId': 'cancel-write',
        'localPath': '/cache/source',
        'kind': 'file',
      });
      await copying.future;
      await coordinator.request('documents.cancel', {
        'operationId': 'cancel-write',
      });
      // The bytes may already have reached the provider when cancellation
      // overtakes the Rust reply. Their save has not been confirmed.
      f.nodes['file']!['size'] = 3;
      copied.complete({
        'bytes': 3,
        'identity': {'kind': 'file', 'size': 3},
      });
      final result = await job;
      expect(result['status'], 'cancelled');
      expect(result['files'], 0);
      expect(result['bytes'], 3);
      expect(result['partialDestinationPossible'], isTrue);
      expect(result['cacheRetained'], isTrue);
      expect(result['uri'], 'content://fixture/file');
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'cancelled'),
      );
      expect(
        f.calls
            .singleWhere((call) => call.$1 == 'documents.platform.releaseFd')
            .$2['outcome'],
        'abort',
      );
      expect(f.calls.where((call) => call.$1 == 'document.copy'), hasLength(1));
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.delete'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );

  test('a missing provider lease leaves the save result unknown', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'saved.txt', size: 0);
    f.local['/cache/source'] = {'kind': 'file', 'size': 3};
    final coordinator = DocumentsCoordinator(
      core: f.core,
      platform: (command, params) async {
        if (command == 'documents.platform.releaseFd') {
          return {'released': false};
        }
        return f.platform(command, params);
      },
    );
    final result = await coordinator.request('documents.export', {
      'localPath': '/cache/source',
      'kind': 'file',
    });
    expect(result['status'], 'resultUnknown');
    expect(result['files'], 0);
    expect(result['partialDestinationPossible'], isTrue);
    expect(result['cacheRetained'], isTrue);
    expect(result['uri'], 'content://fixture/file');
    expect(f.calls.where((call) => call.$1 == 'document.copy'), hasLength(1));
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.delete'),
      isEmpty,
    );
    await coordinator.dispose();
  });

  test(
    'provider close failure leaves write receipt unknown and never retries',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['files'], 0);
      expect(f.calls.where((c) => c.$1 == 'document.copy'), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );
  test(
    'read descriptor close failure removes only its unpublished cache part',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'data.txt');
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['items'], isEmpty);
      expect(f.calls.where((c) => c.$1 == 'document.commit'), isEmpty);
      expect(f.calls.where((c) => c.$1 == 'document.remove'), hasLength(1));
    },
  );

  test(
    'exporting an empty source tree creates its real empty destination',
    () async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.local['/cache/source'] = {'kind': 'directory'};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Empty',
      });
      expect(result['status'], 'saved');
      expect(result['directories'], 1);
      expect(result['files'], 0);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'existing provider names wait for a shared decision and keep both preserves originals',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final job = f.coordinator.request('documents.export', {
        'operationId': 'conflicting-tree',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await tester.pump();
      final pending =
          (await f.coordinator.request('documents.conflict.get', {
                'operationId': 'conflicting-tree',
              }))['pending']
              as DocumentsJson;
      expect(pending['name'], 'Tree');
      expect(pending['choices'], ['keepBoth', 'skip', 'cancel']);
      expect(pending['replacementSupported'], false);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        isEmpty,
      );
      expect(
        await f.coordinator.request('documents.conflict.resolve', {
          'operationId': 'conflicting-tree',
          'conflictId': pending['conflictId'],
          'choice': 'keepBoth',
        }),
        containsPair('resolved', true),
      );
      final result = await job;
      expect(result['status'], 'saved');
      expect(f.nodes['old']!['name'], 'Tree');
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.conflict'),
        isEmpty,
      );
      expect((result['renamed'] as List<Object?>), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );

  test(
    'shared document names preserve Unicode and reject path escapes',
    () async {
      for (final name in [
        '',
        '.',
        '..',
        '../outside',
        'nested/file',
        r'nested\file',
        'nul\u0000name',
        'line\nname',
        'a' * 256,
      ]) {
        final f = Fixture()..selected = ['bad'];
        f.node('bad', name);
        final response = await f.coordinator.request('documents.importFiles');
        expect(response['status'], 'partial', reason: name);
        expect(
          f.calls.where((c) => c.$1 == 'document.copy'),
          isEmpty,
          reason: name,
        );
      }
      for (final name in [
        '中文 empty',
        'file.bin',
        '.hidden',
        'name with spaces',
      ]) {
        final f = Fixture()..selected = ['good'];
        f.node('good', name);
        expect(
          (await f.coordinator.request('documents.importFiles'))['status'],
          'imported',
        );
      }
    },
  );

  test(
    'shared import plans files and empty directories; all owned FDs release',
    () async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      f.node('empty', 'Empty', directory: true);
      f.node('file', 'data.txt');
      f.children['root'] = ['empty', 'file'];
      final result = await f.coordinator.request('documents.importDirectory', {
        'operationId': 'tree',
      });
      expect(result['status'], 'imported');
      expect(result['directories'], 2);
      expect(result['files'], 1);
      expect(result['bytes'], 3);
      expect(f.local.keys.any((path) => path.endsWith('/Tree/Empty')), isTrue);
      expect(
        f.calls
            .where((c) => c.$1 == 'documents.platform.releaseFd')
            .single
            .$2['fdLeaseId'],
        'lease-file',
      );
      expect(f.calls.last.$1, 'documents.platform.release');
    },
  );
  test(
    'provider source changes never publish an unverified cache file',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..mutateSource = true;
      f.node('file', 'data.txt');
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['files'], 0);
      expect(result['items'], isEmpty);
      expect(f.calls.where((c) => c.$1 == 'document.commit'), isEmpty);
      expect(f.calls.where((c) => c.$1 == 'document.remove'), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.releaseFd'),
        hasLength(1),
      );
    },
  );
  test(
    'duplicate provider names remain partial and are never silently merged',
    () async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      f.node('a', 'same');
      f.node('b', 'same');
      f.children['root'] = ['a', 'b'];
      final result = await f.coordinator.request('documents.importDirectory');
      expect(result['status'], 'partial');
      expect(result['files'], 1);
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'duplicate_name'),
      );
    },
  );
  test(
    'each selected same-name file keeps its independent cache root',
    () async {
      final f = Fixture()..selected = ['a', 'b'];
      f.node('a', 'same');
      f.node('b', 'same');
      final result = await f.coordinator.request('documents.importFiles');
      final items = result['items'] as List<DocumentsJson>;
      expect(result['status'], 'imported');
      expect(items, hasLength(2));
      expect(items[0]['localPath'], isNot(items[1]['localPath']));
    },
  );
  test(
    'cancellation is matched to its owner and late picker receipts cannot copy',
    () async {
      final f = Fixture()..picker = Completer<DocumentsJson>();
      final job = f.coordinator.request('documents.importFiles', {
        'operationId': 'owned',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        (await f.coordinator.request('documents.cancel', {
          'operationId': 'other',
        }))['cancelled'],
        isFalse,
      );
      expect(
        (await f.coordinator.request('documents.cancel', {
          'operationId': 'owned',
        }))['cancelled'],
        isTrue,
      );
      expect((await job)['status'], 'cancelled');
      expect(f.calls.where((c) => c.$1 == 'document.copy'), isEmpty);
      expect(
        f.calls
            .where((c) => c.$1 == 'document.cancel')
            .single
            .$2['operationId'],
        'owned',
      );
      await expectLater(
        f.coordinator.request('documents.importFiles', {
          'operationId': 'owned',
        }),
        throwsA(isA<InteropException>()),
      );
    },
  );
  test(
    'uncertain provider create never retries or deletes an existing document',
    () async {
      final f = Fixture()
        ..selected = ['parent']
        ..loseCreate = true;
      f.node('parent', 'Destination', directory: true);
      f.local['/cache/source'] = {'kind': 'directory'};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'name': 'Tree',
        'kind': 'directory',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['partialDestinationPossible'], isTrue);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        hasLength(1),
      );
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );
}
