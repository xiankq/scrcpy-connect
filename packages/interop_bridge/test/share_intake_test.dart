import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/share_intake.dart';

typedef Json = Map<String, dynamic>;

class Fixture {
  final calls = <(String, Json)>[];
  bool disposed = false;
  String? failRelease;
  Completer<Json>? importAck;
  Completer<Json>? opened;
  final importStarted = Completer<void>();
  final openStarted = Completer<void>();
  late final intake = ShareIntake(
    core: core,
    platform: platform,
    isDisposed: () => disposed,
  );

  Future<Json> core(String command, Json params) async {
    calls.add((command, params));
    if (command == 'sharing.import') {
      importStarted.complete();
      return importAck?.future ?? {'status': 'starting'};
    }
    return {};
  }

  Future<Json> platform(String command, Json params) async {
    calls.add((command, params));
    switch (command) {
      case 'sharing.platform.environment':
        return {'cacheDirectory': '/cache'};
      case 'sharing.platform.open':
        if (!openStarted.isCompleted) openStarted.complete();
        return opened?.future ?? descriptor(params['index'] as int);
      case 'sharing.platform.release':
        if (params['fdLeaseId'] == failRelease) {
          throw StateError('OS close failed');
        }
    }
    return {};
  }

  Json descriptor(int index) => {
    'fdLeaseId': 'lease-$index',
    'fd': 100 + index,
    'offset': 7,
    'declaredLength': 12,
    'name': 'file-$index',
  };

  bool called(String command) => calls.any((call) => call.$1 == command);
  List<Json> arguments(String command) => [
    for (final call in calls)
      if (call.$1 == command) call.$2,
  ];
}

void main() {
  test(
    'original descriptors stay open until Rust acknowledges ownership',
    () async {
      final fixture = Fixture()..importAck = Completer<Json>();
      final operation = fixture.intake.receive({
        'shareId': 'share',
        'sourceCount': 2,
      });
      await fixture.importStarted.future;
      expect(fixture.called('sharing.platform.release'), isFalse);
      expect(fixture.called('sharing.platform.consume'), isFalse);
      expect(fixture.arguments('sharing.import').single['sources'], [
        for (var index = 0; index < 2; index++)
          {...fixture.descriptor(index)}..remove('fdLeaseId'),
      ]);
      fixture.importAck!.complete({'status': 'starting'});
      await operation;
      expect(fixture.arguments('sharing.platform.release'), [
        {'fdLeaseId': 'lease-0'},
        {'fdLeaseId': 'lease-1'},
      ]);
      expect(fixture.called('sharing.platform.consume'), isTrue);
    },
  );

  test(
    'late provider response after detach is closed without importing',
    () async {
      final fixture = Fixture()..opened = Completer<Json>();
      final operation = fixture.intake.receive({
        'shareId': 'share',
        'sourceCount': 1,
      });
      await fixture.openStarted.future;
      fixture.disposed = true;
      await fixture.intake.detach();
      expect(fixture.arguments('sharing.platform.cancel'), hasLength(1));
      fixture.opened!.complete(fixture.descriptor(0));
      await operation;
      expect(fixture.called('sharing.import'), isFalse);
      expect(fixture.called('sharing.reject'), isFalse);
      expect(fixture.arguments('sharing.platform.release'), [
        {'fdLeaseId': 'lease-0'},
      ]);
    },
  );

  test(
    'a failed OS close does not prevent closing the remaining descriptors',
    () async {
      final fixture = Fixture()..failRelease = 'lease-0';
      await expectLater(
        fixture.intake.receive({'shareId': 'share', 'sourceCount': 2}),
        throwsStateError,
      );
      expect(fixture.arguments('sharing.platform.release'), [
        {'fdLeaseId': 'lease-0'},
        {'fdLeaseId': 'lease-1'},
      ]);
    },
  );

  test(
    'concurrent delivery of one pending share hands off only once',
    () async {
      final fixture = Fixture()..importAck = Completer<Json>();
      final first = fixture.intake.receive({
        'shareId': 'share',
        'sourceCount': 1,
      });
      await fixture.importStarted.future;
      final second = fixture.intake.receive({
        'shareId': 'share',
        'sourceCount': 1,
      });
      fixture.importAck!.complete({'status': 'starting'});
      await Future.wait([first, second]);
      expect(fixture.arguments('sharing.import'), hasLength(1));
      expect(fixture.arguments('sharing.platform.open'), hasLength(1));
      expect(fixture.arguments('sharing.platform.release'), hasLength(1));
    },
  );
}
