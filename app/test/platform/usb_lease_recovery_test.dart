import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/platform/usb_lease_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('真实 channel begin 与 complete 回执丢失仍以同候选重试，ready 不跳过接管', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    String? nativeOwner = 'old';
    var ready = true, beginReplies = 0, completeReplies = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final params = Map<String, dynamic>.from(call.arguments as Map);
      calls.add((call.method, params));
      switch (call.method) {
        case 'usb.environment':
          return {'ownerLeaseId': nativeOwner, 'ownerReady': ready};
        case 'usb.beginRecovery':
          nativeOwner = params['ownerLeaseId'] as String;
          ready = false;
          if (beginReplies++ == 0) throw PlatformException(code: 'reply_lost');
          return {
            'begun': true,
            'ownerLeaseId': nativeOwner,
            'ownerReady': false,
          };
        case 'usb.completeRecovery':
          ready = true;
          if (completeReplies++ == 0) {
            throw PlatformException(code: 'reply_lost');
          }
          return {
            'completed': true,
            'ownerLeaseId': nativeOwner,
            'ownerReady': true,
          };
      }
      throw StateError('意外的平台命令。');
    });
    final recovery = UsbLeaseRecovery();
    expect(() => recovery.ownerLeaseId, throwsStateError);
    expect(recovery.complete, throwsStateError);
    await expectLater(recovery.begin(), throwsA(_code('reply_lost')));
    expect(() => recovery.ownerLeaseId, throwsStateError);
    await recovery.begin();
    // begin 完成不自动 complete；这里由宿主执行 SDK 的实际排空。
    expect(calls.map((call) => call.$1), [
      'usb.environment',
      'usb.beginRecovery',
      'usb.beginRecovery',
    ]);
    await expectLater(recovery.complete(), throwsA(_code('reply_lost')));
    expect(() => recovery.ownerLeaseId, throwsStateError);
    await recovery.begin();
    await recovery.complete();
    final begin = calls
        .where((call) => call.$1 == 'usb.beginRecovery')
        .map((call) => call.$2)
        .toList();
    expect(begin[1], begin[0]);
    expect(begin[0]['expectedOwnerLeaseId'], 'old');
    final candidate = begin[0]['ownerLeaseId'] as String;
    expect(candidate, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(candidate, isNot('old'));
    expect(recovery.ownerLeaseId, candidate);
    expect(
      calls
          .where((call) => call.$1 == 'usb.completeRecovery')
          .map((call) => call.$2),
      [
        {'ownerLeaseId': candidate},
        {'ownerLeaseId': candidate},
      ],
    );
    final count = calls.length;
    await recovery.begin();
    await recovery.complete();
    expect(calls.length, count);
  });

  test('并发调用合并同一在途 future，不在等待中生成替代候选或提前交付权限', () async {
    final beginStarted = Completer<void>(), completeStarted = Completer<void>();
    final beginReply = Completer<Map<String, dynamic>>(),
        completeReply = Completer<Map<String, dynamic>>();
    final calls = <String>[];
    String? candidate;
    final recovery = UsbLeaseRecovery(
      platform: (command, params) async {
        calls.add(command);
        if (command == 'usb.environment') {
          return {'ownerLeaseId': null, 'ownerReady': false};
        }
        candidate = params['ownerLeaseId'] as String;
        if (command == 'usb.beginRecovery') {
          beginStarted.complete();
          return beginReply.future;
        }
        completeStarted.complete();
        return completeReply.future;
      },
    );
    final first = recovery.begin();
    expect(identical(recovery.begin(), first), isTrue);
    await beginStarted.future;
    expect(recovery.complete, throwsStateError);
    expect(() => recovery.ownerLeaseId, throwsStateError);
    beginReply.complete({
      'begun': true,
      'ownerReady': false,
      'ownerLeaseId': candidate,
    });
    await first;
    final completing = recovery.complete();
    expect(identical(recovery.complete(), completing), isTrue);
    await completeStarted.future;
    expect(() => recovery.ownerLeaseId, throwsStateError);
    completeReply.complete({
      'completed': true,
      'ownerReady': true,
      'ownerLeaseId': candidate,
    });
    await completing;
    expect(recovery.ownerLeaseId, candidate);
    expect(calls, [
      'usb.environment',
      'usb.beginRecovery',
      'usb.completeRecovery',
    ]);
  });

  for (final environment in <Map<String, dynamic>>[
    {},
    {'ownerReady': 1},
    {'ownerReady': true, 'ownerLeaseId': null},
    {'ownerReady': true, 'ownerLeaseId': ''},
    {'ownerReady': true, 'ownerLeaseId': '   '},
    {'ownerReady': false, 'ownerLeaseId': 'bad\u0000lease'},
    {'ownerReady': false, 'ownerLeaseId': 'bad\u0085lease'},
    {'ownerReady': true, 'ownerLeaseId': 'x' * 257},
    {'ownerReady': false, 'ownerLeaseId': 3},
    {'ownerReady': 'true', 'ownerLeaseId': null},
  ]) {
    test('拒绝无效环境 $environment，不提交候选准入', () async {
      final calls = <String>[];
      final recovery = UsbLeaseRecovery(
        platform: (command, _) async {
          calls.add(command);
          return environment;
        },
      );
      await expectLater(
        recovery.begin(),
        throwsA(_code('usb_cleanup_unconfirmed')),
      );
      expect(calls, ['usb.environment']);
      expect(() => recovery.ownerLeaseId, throwsStateError);
    });
  }

  test('begin 回执必须确认本候选，失败重试不重新读取后继环境', () async {
    final candidates = <String>[];
    var environments = 0;
    final recovery = UsbLeaseRecovery(
      platform: (command, params) async {
        if (command == 'usb.environment') {
          environments++;
          return {'ownerReady': true, 'ownerLeaseId': 'previous'};
        }
        candidates.add(params['ownerLeaseId'] as String);
        return {
          'begun': true,
          'ownerReady': false,
          'ownerLeaseId': candidates.length == 1
              ? 'successor'
              : candidates.last,
        };
      },
    );
    await expectLater(
      recovery.begin(),
      throwsA(_code('usb_cleanup_unconfirmed')),
    );
    await recovery.begin();
    expect(candidates[1], candidates[0]);
    expect(environments, 1);
    expect(() => recovery.ownerLeaseId, throwsStateError);
  });

  for (final ready in [null, 1, 'false']) {
    test('begin 缺失或伪造 ownerReady=$ready 不推进阶段，原候选可重试', () async {
      final candidates = <String>[];
      var first = true;
      final recovery = UsbLeaseRecovery(
        platform: (command, params) async {
          if (command == 'usb.environment') {
            return {'ownerReady': false, 'ownerLeaseId': null};
          }
          final candidate = params['ownerLeaseId'] as String;
          candidates.add(candidate);
          if (first) {
            first = false;
            return {
              'begun': true,
              'ownerLeaseId': candidate,
              'ownerReady': ?ready,
            };
          }
          return {
            'begun': true,
            'ownerLeaseId': candidate,
            'ownerReady': false,
          };
        },
      );
      await expectLater(
        recovery.begin(),
        throwsA(_code('usb_cleanup_unconfirmed')),
      );
      expect(recovery.complete, throwsStateError);
      await recovery.begin();
      expect(candidates[1], candidates[0]);
    });
  }

  for (final bad in <Map<String, dynamic>>[
    {},
    {'completed': true, 'ownerReady': false},
    {'completed': false, 'ownerReady': true},
    {'completed': true, 'ownerReady': 'true'},
    {'completed': true, 'ownerReady': true, 'ownerLeaseId': 'other'},
  ]) {
    test('complete 严格拒绝无效确认 $bad，保留同候选重试', () async {
      final candidates = <String>[];
      var first = true;
      final recovery = UsbLeaseRecovery(
        platform: (command, params) async {
          if (command == 'usb.environment') {
            return {'ownerReady': false, 'ownerLeaseId': null};
          }
          final candidate = params['ownerLeaseId'] as String;
          if (command == 'usb.beginRecovery') {
            return {
              'begun': true,
              'ownerReady': false,
              'ownerLeaseId': candidate,
            };
          }
          candidates.add(candidate);
          if (first) {
            first = false;
            return {
              ...bad,
              if (!bad.containsKey('ownerLeaseId')) 'ownerLeaseId': candidate,
            };
          }
          return {
            'completed': true,
            'ownerReady': true,
            'ownerLeaseId': candidate,
          };
        },
      );
      await recovery.begin();
      await expectLater(
        recovery.complete(),
        throwsA(_code('usb_cleanup_unconfirmed')),
      );
      expect(() => recovery.ownerLeaseId, throwsStateError);
      await recovery.complete();
      expect(candidates[1], candidates[0]);
      expect(recovery.ownerLeaseId, candidates[0]);
    });
  }
}

Matcher _code(String code) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  code,
);
