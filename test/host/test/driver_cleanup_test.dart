import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../../driver/support/cleanup.dart';
import '../../driver/support/android_ui.dart';
import '../../driver/support/capture.dart';
import '../../driver/support/inspection.dart';

void main() {
  test('检查点等待扩展注册、去重并回传核验错误与结果', () async {
    final inspected = <String>[];
    final acknowledgements = <Map<String, String>>[];
    final completed = Completer<void>();
    final failure = StateError('target state differs');
    var reads = 0;
    final inspection = DriverInspection(
      interval: Duration.zero,
      request: ([args]) async {
        if (args != null) {
          acknowledgements.add(args);
          if (args['ack'] == 'second') completed.complete();
          return {};
        }
        reads++;
        if (reads == 1) throw StateError('Method not found: -32601');
        return {
          'checkpoint': {'id': reads < 4 ? 'first' : 'second'},
        };
      },
      inspect: (checkpoint) async {
        inspected.add(checkpoint['id'] as String);
        if (checkpoint['id'] == 'first') throw failure;
        return {'verified': true};
      },
    );
    await completed.future.timeout(const Duration(seconds: 1));
    await inspection.stop();
    expect(inspected, ['first', 'second']);
    expect(acknowledgements, [
      {'ack': 'first', 'error': '$failure'},
      {'ack': 'second', 'result': '{"verified":true}'},
    ]);
    expect(inspection.error, same(failure));
  });

  test('停止检查点核验时先排空在途任务，随后恢复且不再回执', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final order = <String>[];
    final inspection = DriverInspection(
      request: ([args]) async {
        expect(args, isNull, reason: '停止之后不能回执旧检查点。');
        return {
          'checkpoint': {'id': 'in-flight'},
        };
      },
      inspect: (_) async {
        entered.complete();
        await release.future;
        order.add('inspection-drained');
        return null;
      },
    );
    await entered.future;
    final cleanup = withDriverCleanup(
      () async {},
      () => {
        'inspection': inspection.stop,
        'device': () => order.add('device-restored'),
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(order, isEmpty);
    release.complete();
    await cleanup;
    await inspection.stop();
    expect(order, ['inspection-drained', 'device-restored']);
  });

  test('系统 UI 节点保留实体、祖先和自闭合节点，拒绝损坏层级', () {
    final nodes = parseAndroidUi(r'''<?xml version="1.0"?>
<hierarchy><node resource-id="root"><node resource-id="item">
<node text="&quot;&apos;&lt;&gt;&amp;amp;&#x4e2d;" bounds="[0,1][2,3]"/>
</node><node text="sibling"/></node></hierarchy>''');
    expect(nodes.map((node) => node['text']), [
      '',
      '',
      '"\'<>&amp;中',
      'sibling',
    ]);
    expect(nodes[2]['bounds'], '[0,1][2,3]');
    expect(nodes[2].ancestors.map((node) => node['resource-id']), [
      'item',
      'root',
    ]);
    expect(nodes.last.ancestors.map((node) => node['resource-id']), ['root']);
    expect(nodes.first['missing'], '');
    expect(
      () => parseAndroidUi('<hierarchy><node></hierarchy>'),
      throwsFormatException,
    );
  });

  test('截图保存净化路径并保留原始字节，拒绝空文件名', () async {
    final root = await Directory.systemTemp.createTemp('driver-capture-');
    addTearDown(() => root.delete(recursive: true));
    final output = Directory('${root.path}/captures');
    expect(await saveScreenshot(output, '../画面/frame', [0, 128, 255]), isTrue);
    expect(await File('${output.path}/______frame.png').readAsBytes(), [
      0,
      128,
      255,
    ]);
    expect(await output.list().length, 1);
    await expectLater(saveScreenshot(output, '', [1]), throwsArgumentError);
    expect(await output.list().length, 1);
  });

  test('恢复失败后仍按顺序等待其他设备和夹具的恢复', () async {
    final calls = <String>[];
    final release = Completer<void>();
    final operation = withDriverCleanup(
      () async {},
      () => {
        'foreground': () => throw StateError('foreground unavailable'),
        'first clipboard': () async {
          calls.add('first-start');
          await release.future;
          calls.add('first-end');
          throw StateError('first endpoint unavailable');
        },
        'second clipboard': () => calls.add('second-restored'),
        'fixture': () => calls.add('fixture-removed'),
      },
    );
    final failure = expectLater(
      operation,
      throwsA(
        isA<DriverCleanupException>().having(
          (error) => error.failures.map((failure) => failure.step),
          'failed steps',
          ['foreground', 'first clipboard'],
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first-start']);
    release.complete();
    await failure;
    expect(calls, [
      'first-start',
      'first-end',
      'second-restored',
      'fixture-removed',
    ]);
  });

  test('收尾成功时原始故障和堆栈原样返回', () async {
    final primary = StateError('capture failed');
    final stack = StackTrace.fromString('original capture stack');
    try {
      await withDriverCleanup(
        () => Future<void>.error(primary, stack),
        () => {'fixture': () {}},
      );
      fail('Expected capture failure');
    } catch (error, actualStack) {
      expect(error, same(primary));
      expect(actualStack.toString(), stack.toString());
    }
  });

  test('收尾故障同时保留主错误、原堆栈及全部恢复失败', () async {
    final primary = StateError('capture failed');
    final stack = StackTrace.fromString('original capture stack');
    try {
      await withDriverCleanup(
        () => Future<void>.error(primary, stack),
        () => {
          'settings': () => throw StateError('setting failed'),
          'fixture': () => throw StateError('uninstall failed'),
        },
      );
      fail('Expected combined failure');
    } on DriverCleanupException catch (error, actualStack) {
      expect(error.primaryError, same(primary));
      expect(error.primaryStack, same(stack));
      expect(actualStack.toString(), stack.toString());
      expect(error.failures.map((failure) => failure.step), [
        'settings',
        'fixture',
      ]);
      expect(error.toString(), contains('capture failed'));
      expect(error.toString(), contains('setting failed'));
      expect(error.toString(), contains('uninstall failed'));
    }
  });

  test('无回执的 VM 读取有界结束，停止并排空后才恢复设备', () async {
    var stopped = false;
    var requestCount = 0;
    final order = <String>[];
    final neverReplies = Completer<void>();
    final inspection = () async {
      while (!stopped) {
        requestCount++;
        try {
          await driverRpc(
            neverReplies.future,
            timeout: const Duration(milliseconds: 20),
          );
        } on TimeoutException {
          if (!stopped) rethrow;
        }
      }
      order.add('inspection-drained');
    }();
    await withDriverCleanup(
      () async {},
      () => {
        'inspection': () async {
          stopped = true;
          await inspection;
        },
        'device settings': () => order.add('device-restored'),
      },
    );
    expect(requestCount, 1);
    expect(order, ['inspection-drained', 'device-restored']);
    neverReplies.complete();
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);
  });
}
