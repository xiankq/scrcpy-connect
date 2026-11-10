import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_connect/services/file_transfer_service.dart';

import 'file_executor_fixture.dart';

Future<void> withTransfer(
  Future<void> Function(FileTransferService, FixtureExecutor, Directory) check,
) async {
  final root = await Directory.systemTemp.createTemp('file-owner-');
  final executor = FixtureExecutor();
  final owner = await FileTransferService.open(
    executor: executor,
    dataDirectory: root,
  );
  try {
    await check(owner, executor, root);
  } finally {
    await owner.close();
    await root.delete(recursive: true);
  }
}

final transferChecks = <String, Future<void> Function()>{
  'file transaction persists finalizing before commit and resolves conflicts':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.stamps['/sdcard/existing'] = regular;
          executor.contents['/sdcard/existing'] = [9];
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/existing'},
          ]);
          final id = receipt['transferId']! as String;
          await until(() => owner.transfer(id)['status'] == 'conflict');
          require(
            !executor.calls.any((c) => c.startsWith('copy:')),
            'copied bytes before conflict decision',
          );
          executor.beforeCommit = (part, target) async {
            final records = await File('${root.path}/file_tasks.v2.journal')
                .readAsLines();
            final latest =
                records
                        .map((line) => jsonDecode(line) as Map)
                        .where((r) => (r['task'] as Map?)?['id'] == id)
                        .last['task']
                    as Map;
            require(
              latest['status'] == 'finalizing' &&
                  latest['temporaryPath'] == part,
              'commit preceded durable finalizing record',
            );
            require(
              !executor.contents.containsKey(target),
              'published before commit',
            );
          };
          await owner.resolveTransfer(id, 'keepBoth');
          await until(() => owner.transfer(id)['status'] == 'completed');
          require(
            executor.contents['/sdcard/existing']!.single == 9 &&
                executor.contents['/sdcard/existing (1)']!.length == 4,
            'keepBoth overwrote existing data',
          );
        });
      },
  'cancellation waits for worker cleanup and never publishes partial files':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.blockCopy = true;
          executor.copyStarted = Completer<void>();
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/new'},
          ]);
          await executor.copyStarted!.future;
          final id = receipt['transferId']! as String;
          await owner.cancelTransfer(id);
          require(
            owner.transfer(id)['status'] == 'cancelled',
            'cancel returned before terminal worker result',
          );
          require(
            !executor.contents.containsKey('/sdcard/new') &&
                !executor.calls.any((c) => c.startsWith('commit:')),
            'cancelled bytes were published',
          );
        });
      },
  'legacy migration is read-only and unknown commit cannot be retried':
      () async {
        final root = await Directory.systemTemp.createTemp('file-migration-');
        final legacy = File('${root.path}/transfers.json');
        final raw = jsonEncode({
          'version': 1,
          'sequence': 1,
          'transfers': [
            {
              'id': 'old',
              'batchId': 'old',
              'deviceId': 'd',
              'direction': 'pull',
              'source': '/sdcard/s',
              'destination': '${root.path}/kept',
              'kind': 'file',
              'status': 'finalizing',
              'policy': 'ask',
              'generation': 2,
              'transferred': 4,
              'total': 4,
              'sourceStamp': regular.toJson(),
            },
          ],
        });
        await legacy.writeAsString(raw, flush: true);
        await File('${root.path}/kept').writeAsString('user data', flush: true);
        final owner = await FileTransferService.open(
          executor: FixtureExecutor(),
          dataDirectory: root,
        );
        try {
          final task = owner.transfer('old');
          require(
            task['status'] == 'interrupted' &&
                task['errorCode'] == 'result_unknown' &&
                task['canRestart'] == false,
            'unknown commit became retryable',
          );
          require(
            await legacy.readAsString() == raw &&
                await File('${root.path}/kept').readAsString() == 'user data',
            'migration modified legacy journal or user data',
          );
        } finally {
          await owner.close();
          await root.delete(recursive: true);
        }
      },
  'missing commit receipt preserves source and refuses automatic replay':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.unknownCommit = true;
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/new'},
          ]);
          final id = receipt['transferId']! as String;
          await until(() => owner.transfer(id)['status'] == 'failed');
          require(
            owner.transfer(id)['errorCode'] == 'result_unknown' &&
                owner.transfer(id)['canRestart'] == false,
            'lost receipt was classified as safely retryable',
          );
          require(executor.stamps.containsKey('/source'), 'source was deleted');
        });
      },
};
