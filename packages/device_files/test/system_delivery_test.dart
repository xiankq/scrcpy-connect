import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_files/device_files.dart';
import 'package:device_protocol/device_protocol.dart' show InteropException;

void main() {
  test('a full receipt that cannot fit falls back to durable unknown without writing again', () async {
    var writes = 0;
    var receipts = 0;
    final delivery = SystemDelivery(
      core: (command, params) async {
        if (command == 'delivery.begin') {
          return {
            'record': {'status': 'pending'},
          };
        }
        if (command == 'delivery.finish') {
          if (++receipts == 1) {
            throw const InteropException(
              'delivery_capacity',
              'receipt too large',
            );
          }
          return {
            'record': {'result': params['result']},
          };
        }
        throw StateError(command);
      },
      write: (_) async {
        writes++;
        return {'status': 'saved', 'name': 'a'};
      },
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
    expect(writes, 1);
    expect(receipts, 2);
  });
  test(
    'a coordinator rejection before any provider work is a safe failed attempt',
    () async {
      final delivery = SystemDelivery(
        core: (command, params) async {
          if (command == 'delivery.begin') {
            return {
              'record': {'status': 'pending'},
            };
          }
          if (command == 'delivery.finish') {
            return {
              'record': {'result': params['result']},
            };
          }
          throw StateError(command);
        },
        write: (_) async {
          throw const InteropException('documents_busy', '已有系统文档任务');
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
      final delivery = SystemDelivery(
        core: (command, params) async {
          if (command == 'delivery.begin') return admission.future;
          if (command == 'delivery.finish') {
            completed = params['result'] as Map<String, dynamic>;
            return {
              'record': {'result': completed},
            };
          }
          throw StateError(command);
        },
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
    final delivery = SystemDelivery(
      core: (command, params) async {
        if (command == 'delivery.begin') return admission.future;
        if (command == 'delivery.finish') return receipt.future;
        throw StateError(command);
      },
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
