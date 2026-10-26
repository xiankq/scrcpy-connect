import 'dart:async';
import 'dart:convert';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/files/desktop_document_delivery.dart';

import 'documents_coordinator_test.dart' show Fixture, identity;

import 'package:scrcpy_connect/stores/files/system_delivery_coordinator.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart'
    show ApplicationCommandException;

ApplicationRequest _journal({
  Future<Json>? admission,
  FutureOr<Json> Function(Json)? finish,
}) => (command, [params = const {}]) async {
  if (command == 'delivery.begin') {
    return admission ??
        {
          'record': {'status': 'pending'},
        };
  }
  if (command != 'delivery.finish') throw StateError(command);
  return finish?.call(params) ??
      {
        'record': {'result': params['result']},
      };
};

void main() {
  test('a full receipt that cannot fit falls back to durable unknown without writing again', () async {
    var receipts = 0;
    final fixture = Fixture();
    fixture.local.addAll({
      '/cache/a': {'kind': 'file', 'size': 3},
      '/target': {'kind': 'directory'},
      '/target/a': {'kind': 'file', 'size': 7},
    });
    fixture.nativeFiles.onStat = (path) async {
      final entry = fixture.local[utf8.decode(path)];
      if (entry == null) {
        throw const LocalFileException(
          LocalFileErrorCode.notFound,
          'not found',
        );
      }
      return LocalFileStat(
        identity: identity(entry),
        freeBytes: BigInt.from(1000000000),
      );
    };
    late final DesktopDocumentDelivery desktop;
    desktop = DesktopDocumentDelivery(
      files: fixture.files,
      pick: (_, _) async => '/target/a',
      emit: (event) {
        if (event['pending'] case final Map<Object?, Object?> pending) {
          desktop.request('documents.conflict.resolve', {
            'operationId': event['operationId'],
            'conflictId': pending['conflictId'],
            'choice': 'keepBoth',
          }).ignore();
        }
      },
    );
    addTearDown(desktop.dispose);
    final delivery = SystemDeliveryCoordinator(
      applicationRequest: _journal(
        finish: (params) {
          if (++receipts == 1) {
            throw const ApplicationCommandException(
              'delivery_capacity',
              'receipt too large',
            );
          }
          return {
            'record': {'result': params['result']},
          };
        },
      ),
      write: desktop.write,
    );
    final result = await delivery.save({
      'sourceId': 'transfer:a',
      'localPath': '/cache/a',
      'kind': 'file',
      'name': 'a',
      'operationId': 'one-write',
    });
    expect(result['status'], 'result_unknown');
    expect(result['partialDestinationPossible'], true);
    expect(receipts, 2);
    expect(fixture.local['/target/a']?['size'], 7);
    expect(
      fixture.calls.where((call) => call.$1 == 'local.commit'),
      hasLength(1),
    );
    fixture.nativeFiles.onCommit = (_) async => throw const LocalFileException(
      LocalFileErrorCode.resultUnknown,
      'publication receipt lost',
    );
    expect(
      (await desktop.write({
        'operationId': 'unknown-publish',
        'localPath': '/cache/a',
        'kind': 'file',
        'name': 'a',
      }))['status'],
      'result_unknown',
    );
  });
  test(
    'a coordinator rejection before any provider work is a safe failed attempt',
    () async {
      final delivery = SystemDeliveryCoordinator(
        applicationRequest: _journal(),
        write: (_) async {
          throw const ApplicationCommandException('documents_busy', '已有系统文档任务');
        },
      );
      final result = await delivery.save({
        'sourceId': 'transfer:a',
        'localPath': '/cache/a',
        'kind': 'file',
        'name': 'a',
        'operationId': 'preflight',
      });
      expect(result['status'], 'failed');
      expect(result['partialDestinationPossible'], false);
    },
  );
  test(
    'leaving while admission is pending cannot open a late system picker',
    () async {
      final admission = Completer<Map<String, dynamic>>();
      var writes = 0;
      Map<String, dynamic>? completed;
      final delivery = SystemDeliveryCoordinator(
        applicationRequest: _journal(
          admission: admission.future,
          finish: (params) {
            completed = params['result'] as Json;
            return {
              'record': {'result': completed},
            };
          },
        ),
        write: (_) async {
          writes++;
          return {'status': 'saved'};
        },
      );
      final saving = delivery.save({
        'sourceId': 'transfer:a',
        'localPath': '/cache/a',
        'kind': 'file',
        'name': 'a',
        'operationId': 'cancel-before-admission',
      });
      await Future<void>.delayed(Duration.zero);
      await delivery.cancel('cancel-before-admission');
      admission.complete({
        'record': {'status': 'pending'},
      });
      expect((await saving)['status'], 'cancelled');
      expect(writes, 0);
      expect(completed?['partialDestinationPossible'], false);
    },
  );
  test('system writing waits for durable admission and success waits for its receipt', () async {
    final admission = Completer<Map<String, dynamic>>();
    final receipt = Completer<Map<String, dynamic>>();
    var writes = 0;
    var finished = false;
    final delivery = SystemDeliveryCoordinator(
      applicationRequest: _journal(
        admission: admission.future,
        finish: (_) => receipt.future,
      ),
      write: (params) async {
        writes++;
        return {'status': 'saved', 'name': 'original.txt'};
      },
    );
    final result = delivery
        .save({
          'sourceId': 'transfer:source-a',
          'localPath': '/cache/a',
          'kind': 'file',
          'name': 'original.txt',
          'operationId': 'write-a',
        })
        .then((value) {
          finished = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(writes, 0);
    admission.complete({
      'record': {'status': 'pending'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(writes, 1);
    expect(finished, false);
    receipt.complete({
      'record': {
        'result': {'status': 'saved', 'name': 'original.txt'},
      },
    });
    expect((await result)['status'], 'saved');
    expect(finished, true);
  });
}
