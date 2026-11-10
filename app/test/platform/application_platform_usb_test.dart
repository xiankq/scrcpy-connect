import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/platform/application_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.scrcpyconnect/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('固定构造时的权限覆盖请求伪造值，不修改调用方参数', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final params = Map<String, dynamic>.from(call.arguments as Map);
      calls.add((call.method, params));
      return {
        'ownerLeaseId': params['ownerLeaseId'],
        'usbLeaseId': 'fd-lease',
        'fd': 17,
        if (call.method == 'usb.release') 'released': true,
        if (call.method == 'usb.cancel') 'cancelled': true,
      };
    });
    final platform = _platform('fixed-owner');
    final params = <String, dynamic>{
      'attemptId': 'attempt',
      'ownerLeaseId': 'spoof',
    };
    final reply = await platform.authorizeUsb(params);
    expect(reply['usbLeaseId'], 'fd-lease');
    await platform.cancelUsb(params);
    await platform.releaseUsb({...params, 'usbLeaseId': 'fd-lease'});
    expect(calls.map((call) => call.$1), [
      'usb.authorize',
      'usb.cancel',
      'usb.release',
    ]);
    expect(
      calls.map((call) => call.$2['ownerLeaseId']),
      everyElement('fixed-owner'),
    );
    expect(params['ownerLeaseId'], 'spoof');
  });

  test('两个实例权限隔离，旧实例不能读取后继 token 或释放后继 FD', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    var current = 'old';
    final leases = <String, String>{};
    (String, String)? pendingUi = ('old', 'shared-attempt');
    messenger.setMockMethodCallHandler(channel, (call) async {
      final params = Map<String, dynamic>.from(call.arguments as Map);
      calls.add((call.method, params));
      final owner = params['ownerLeaseId'];
      if (call.method == 'usb.cancel') {
        if (pendingUi == (owner, params['attemptId'])) pendingUi = null;
        return {'cancelled': true, 'ownerLeaseId': owner};
      }
      if (owner != current) throw PlatformException(code: 'usb_owner_stale');
      if (call.method == 'usb.authorize') {
        leases['$owner-fd'] = owner as String;
        return {'ownerLeaseId': owner, 'usbLeaseId': '$owner-fd', 'fd': 23};
      }
      if (call.method == 'usb.release') leases.remove(params['usbLeaseId']);
      return {'released': true, 'ownerLeaseId': owner};
    });
    final old = _platform('old');
    expect(
      (await old.authorizeUsb({'attemptId': 'old-attempt'}))['usbLeaseId'],
      'old-fd',
    );
    // 平台 complete 已排空旧资源并交付后继权限。
    leases.clear();
    current = 'new';
    pendingUi = ('new', 'shared-attempt');
    final next = _platform('new');
    await next.authorizeUsb({'attemptId': 'new-attempt'});
    await expectLater(
      old.authorizeUsb({'ownerLeaseId': 'new'}),
      throwsA(_code('usb_owner_stale')),
    );
    await expectLater(
      old.releaseUsb({'ownerLeaseId': 'new', 'usbLeaseId': 'new-fd'}),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'usb_owner_stale',
        ),
      ),
    );
    await old.cancelUsb({'ownerLeaseId': 'new', 'attemptId': 'shared-attempt'});
    expect(pendingUi, ('new', 'shared-attempt'));
    expect(leases, {'new-fd': 'new'});
    expect(calls.sublist(2).map((call) => call.$2['ownerLeaseId']), [
      'old',
      'old',
      'old',
    ]);
    await next.releaseUsb({'usbLeaseId': 'new-fd'});
    expect(leases, isEmpty);
    await next.cancelUsb({'attemptId': 'shared-attempt'});
    expect(pendingUi, isNull);
  });

  test('封存后旧实例仍能撤销精确授权 UI，无匹配或无页面也可确认，释放仍拒绝', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    (String, String)? pendingUi = ('original-owner', 'original-attempt');
    messenger.setMockMethodCallHandler(channel, (call) async {
      final params = Map<String, dynamic>.from(call.arguments as Map);
      calls.add((call.method, params));
      final owner = params['ownerLeaseId'];
      if (call.method == 'usb.cancel') {
        if (pendingUi == (owner, params['attemptId'])) pendingUi = null;
        return {'cancelled': true, 'ownerLeaseId': owner};
      }
      throw PlatformException(code: 'usb_recovery_pending');
    });
    final platform = _platform('original-owner');
    await platform.dispose();
    await platform.cancelUsb({'attemptId': 'unmatched-attempt'});
    expect(pendingUi, ('original-owner', 'original-attempt'));
    await platform.cancelUsb({'attemptId': 'original-attempt'});
    expect(pendingUi, isNull);
    await platform.cancelUsb({'attemptId': 'original-attempt'});
    await expectLater(
      platform.releaseUsb({'usbLeaseId': 'original-fd'}),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'usb_recovery_pending',
        ),
      ),
    );
    expect(
      calls.map((call) => call.$2['ownerLeaseId']),
      everyElement('original-owner'),
    );
  });

  test('授权成功回执晚于 dispose 仍交还精确 FD，清理继续使用原权限', () async {
    final started = Completer<void>();
    final permission = Completer<Map<String, dynamic>>();
    final calls = <(String, Map<String, dynamic>)>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add((
        call.method,
        Map<String, dynamic>.from(call.arguments as Map),
      ));
      if (call.method == 'usb.authorize') {
        started.complete();
        return permission.future;
      }
      return {
        'ownerLeaseId': 'owner',
        if (call.method == 'usb.cancel') 'cancelled': true,
        if (call.method == 'usb.release') 'released': true,
      };
    });
    final platform = _platform('owner');
    final authorization = platform.authorizeUsb({'attemptId': 'late'});
    await started.future;
    await platform.dispose();
    permission.complete({
      'ownerLeaseId': 'owner',
      'usbLeaseId': 'late-fd',
      'fd': 42,
    });
    final reply = await authorization;
    expect(reply['fd'], 42);
    expect(reply['usbLeaseId'], 'late-fd');
    await platform.cancelUsb({'attemptId': 'late'});
    await platform.releaseUsb({'usbLeaseId': reply['usbLeaseId']});
    await expectLater(
      platform.authorizeUsb({'attemptId': 'new'}),
      throwsA(_code('cancelled')),
    );
    expect(calls.map((call) => call.$1), [
      'usb.authorize',
      'usb.cancel',
      'usb.release',
    ]);
    expect(calls.last.$2, {'usbLeaseId': 'late-fd', 'ownerLeaseId': 'owner'});
  });

  test('没有已确认 token 的平台实例明确拒绝 USB，不访问 channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'released': true, 'ownerLeaseId': 'owner'};
    });
    for (final owner in [null, '', '  ', 'bad\u0000lease', 'x' * 257]) {
      final platform = _platform(owner);
      for (final operation in [
        platform.authorizeUsb,
        platform.cancelUsb,
        platform.releaseUsb,
      ]) {
        await expectLater(
          operation({}),
          throwsA(_code('usb_owner_unavailable')),
        );
      }
    }
    expect(calls, isEmpty);
  });

  test('授权必须核对平台回执的 owner，不以请求值替代平台事实', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'ownerLeaseId': 'other', 'usbLeaseId': 'other-fd', 'fd': 9},
    );
    await expectLater(
      _platform('owner').authorizeUsb({}),
      throwsA(_code('usb_owner_mismatch')),
    );
  });

  test('精确释放首败后仍可用相同 owner 与 FD lease 重试', () async {
    final calls = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(Map<String, dynamic>.from(call.arguments as Map));
      if (calls.length == 1) {
        throw PlatformException(code: 'usb_cleanup_unconfirmed');
      }
      return {'released': true, 'ownerLeaseId': 'owner'};
    });
    final platform = _platform('owner');
    await platform.dispose();
    await expectLater(
      platform.releaseUsb({'usbLeaseId': 'exact'}),
      throwsA(isA<PlatformException>()),
    );
    await platform.releaseUsb({'usbLeaseId': 'exact'});
    expect(calls, [
      {'usbLeaseId': 'exact', 'ownerLeaseId': 'owner'},
      {'usbLeaseId': 'exact', 'ownerLeaseId': 'owner'},
    ]);
  });

  for (final (command, bad) in <(String, Object?)>[
    ('usb.release', {'released': false, 'ownerLeaseId': 'owner'}),
    ('usb.release', {'released': true, 'ownerLeaseId': 'other'}),
    ('usb.cancel', null),
  ]) {
    final confirmation = command == 'usb.release' ? 'released' : 'cancelled';
    test('$command 无效回收确认 $bad 保留同实例精确重试权', () async {
      final calls = <Map<String, dynamic>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, command);
        calls.add(Map<String, dynamic>.from(call.arguments as Map));
        if (calls.length == 1) return bad;
        return {confirmation: true, 'ownerLeaseId': 'owner'};
      });
      final platform = _platform('owner');
      final operation = command == 'usb.release'
          ? platform.releaseUsb
          : platform.cancelUsb;
      final params = <String, dynamic>{
        if (command == 'usb.release') 'usbLeaseId': 'exact-fd',
        if (command == 'usb.cancel') 'attemptId': 'exact-attempt',
      };
      await expectLater(
        operation(params),
        throwsA(_code('usb_cleanup_unconfirmed')),
      );
      await operation(params);
      expect(calls, [
        {...params, 'ownerLeaseId': 'owner'},
        {...params, 'ownerLeaseId': 'owner'},
      ]);
    });
  }
}

ApplicationPlatform _platform(String? owner) => ApplicationPlatform(
  applicationRequest: (_, _) async => throw StateError('USB 不应调用应用命令。'),
  localFiles: () async => throw StateError('USB 不应打开文档 scope。'),
  emit: (_) {},
  isDisposed: () => false,
  usbOwnerLeaseId: owner,
);

Matcher _code(String code) =>
    isA<RequestFailure>().having((error) => error.code, 'code', code);
