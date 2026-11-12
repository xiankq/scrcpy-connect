import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';

void main() {
  test('配置缓存后才交付依赖，成功时不关闭所有者', () async {
    final configured = Completer<void>();
    final cache = _Cache(() => configured.future);
    var closes = 0;
    final dependencies = _Dependencies(cache, () async {
      closes++;
    });
    var delivered = false;
    final pending =
        bootstrapApp(
          createDependencies: () async => dependencies,
          prepareOutgoingDirectory: () async => Directory('/outgoing'),
        ).then((value) {
          delivered = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(delivered, isFalse);
    configured.complete();
    expect(await pending, same(dependencies));
    expect(cache.outgoingDirectory, '/outgoing');
    expect(closes, 0);
  });

  test('启动失败等待原所有者清理，清理失败仍报告最初错误', () async {
    final original = StateError('cache configuration');
    final closed = Completer<void>();
    var closing = false;
    final dependencies = _Dependencies(
      _Cache(() async {
        throw original;
      }),
      () {
        closing = true;
        return closed.future;
      },
    );
    final pending = bootstrapApp(
      createDependencies: () async => dependencies,
      prepareOutgoingDirectory: () async => Directory('/outgoing'),
    );
    var completed = false;
    final checked = expectLater(
      pending,
      throwsA(same(original)),
    ).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closing, isTrue);
    expect(completed, isFalse);
    closed.completeError(StateError('close failed'));
    await checked;
  });
}

class _Dependencies implements AppDependencies {
  _Dependencies(this.cache, this.close);
  @override
  final ContentCacheControl cache;
  @override
  final Future<void> Function()? close;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements ContentCacheControl {
  _Cache(this.configureResult);
  final Future<void> Function() configureResult;
  String? outgoingDirectory;
  @override
  Future<void> configure({int? budgetBytes, String? outgoingDirectory}) {
    this.outgoingDirectory = outgoingDirectory;
    return configureResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
