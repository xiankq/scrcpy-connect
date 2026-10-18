import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_bootstrap.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failureAt in ['outgoing directory', 'cache configuration']) {
    test(
      'failed $failureAt releases the exclusive transport before retry',
      () async {
        final transport = _ExclusiveTransport();
        final failure = FileSystemException(failureAt);
        var fail = true;
        Future<AppDependencies> attempt() => bootstrapApplication(
          initializeTransport: () => transport.open(
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
        scope.read(appControllerProvider.notifier);
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
        initializeTransport: () async => AppDependencies(
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
          initializeTransport: () async => AppDependencies(
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

/// Models the bridge's one-owner rule: the next open is rejected until close
/// completes. A permissive request fake cannot catch the broken retry path.
class _ExclusiveTransport {
  bool active = false;
  int closes = 0;
  final requests = <(String, Json)>[];

  Future<AppDependencies> open({Object? configurationFailure}) async {
    if (active) {
      throw const RequestFailure('bridge_already_initialized', 'Already owned');
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
