import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../../driver/support/cleanup.dart';
import '../../driver/support/android_ui.dart';
import '../../driver/support/capture.dart';

void main() {
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
