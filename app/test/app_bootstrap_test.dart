import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/widgets/application_lifecycle.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('应用视图提供可见状态并在退出视图后停止监听', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final visible = <bool>[];
    final lifecycle = ApplicationLifecycle(
      setVisible: (value) async => visible.add(value),
      shutdown: null,
    );
    await lifecycle.attach();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    lifecycle.dispose();
    expect(visible, [true, true, false, false, false]);
    visible.clear();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(visible, isEmpty);
  });

  for (final failureAt in ['outgoing directory', 'cache configuration']) {
    test(
      'failed $failureAt releases the exclusive transport before retry',
      () async {
        final transport = _ExclusiveTransport();
        final failure = FileSystemException(failureAt);
        var fail = true;
        Future<AppDependencies> attempt() => bootstrapApplication(
          createDependencies: () => transport.open(
            configurationFailure: fail && failureAt == 'cache configuration'
                ? failure
                : null,
          ),
          prepareOutgoingDirectory: () async {
            if (fail && failureAt == 'outgoing directory') throw failure;
            return Directory('/temporary/outgoing');
          },
        );

        await expectLater(attempt(), throwsA(same(failure)));
        expect(transport.active, isFalse);
        expect(transport.closes, 1);
        fail = false;
        final dependencies = await attempt();
        expect(transport.active, isTrue);
        expect(transport.closes, 1, reason: 'Success transfers ownership.');
        expect(transport.requests.last.$1, 'media.cache.configure');
        expect(transport.requests.last.$2, {
          'outgoingDirectory': '/temporary/outgoing',
        });

        final scope = ProviderContainer(
          overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        );
        scope.read(appStoreProvider.notifier);
        scope.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(transport.closes, 2);
        expect(transport.active, isFalse);
      },
    );
  }

  test(
    'startup failure waits for transport detach before exposing retry',
    () async {
      final detach = Completer<void>();
      final failure = StateError('directory unavailable');
      var completed = false;
      final pending = bootstrapApplication(
        createDependencies: () async => AppDependencies(
          request: (command, [params = const {}]) async => {},
          close: () => detach.future,
        ),
        prepareOutgoingDirectory: () async => throw failure,
      );
      final checked = expectLater(pending, throwsA(same(failure))).then((_) {
        completed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      detach.complete();
      await checked;
    },
  );

  test(
    'detach failure preserves the original startup error and stack',
    () async {
      final failure = StateError('cache configuration failed');
      final stack = StackTrace.fromString('configuration origin');
      try {
        await bootstrapApplication(
          createDependencies: () async => AppDependencies(
            request: (command, [params = const {}]) async => {},
            close: () async => throw StateError('detach failed'),
          ),
          prepareOutgoingDirectory: () async =>
              Error.throwWithStackTrace(failure, stack),
        );
        fail('Startup must fail.');
      } catch (error, captured) {
        expect(error, same(failure));
        expect(captured.toString(), contains('configuration origin'));
      }
    },
  );
}

/// 模拟应用依赖的单所有者规则：关闭完成前拒绝再次打开；允许任意请求的替身无法发现损坏的重试路径。
class _ExclusiveTransport {
  bool active = false;
  int closes = 0;
  final requests = <(String, Json)>[];

  Future<AppDependencies> open({Object? configurationFailure}) async {
    if (active) {
      throw const RequestFailure(
        'application_already_initialized',
        'Already owned',
      );
    }
    active = true;
    return AppDependencies(
      initialize: false,
      request: (command, [params = const {}]) async {
        requests.add((command, params));
        if (configurationFailure != null) throw configurationFailure;
        return {};
      },
      close: () async {
        closes++;
        active = false;
      },
    );
  }
}
