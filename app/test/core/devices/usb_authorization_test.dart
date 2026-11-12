import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/usb_authorization.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

void main() {
  test('迟到授权仍交回原租约，关闭后可精确取消和释放', () async {
    var disposed = false;
    final authorized = Completer<Json?>();
    final cleanup = <Json>[];
    final usb = UsbAuthorization(
      ownerLeaseId: 'owner',
      isDisposed: () => disposed,
      request: (command, params) async {
        expect(params['ownerLeaseId'], 'owner');
        if (command == 'usb.authorize') {
          expect(params, {
            'ownerLeaseId': 'owner',
            'attemptId': 'attempt',
            'deviceId': 'device',
            'serial': 'requested-serial',
            'usbDeviceId': 'usb-device',
            'connect': true,
          });
          return authorized.future;
        }
        cleanup.add(params);
        return {'ownerLeaseId': 'owner', 'cancelled': true, 'released': true};
      },
    );
    final permission = usb.authorize(
      const UsbAuthorizationRequest(
        attemptId: 'attempt',
        deviceId: 'device',
        serial: 'requested-serial',
        usbDeviceId: 'usb-device',
        connect: true,
      ),
    );
    disposed = true;
    authorized.complete({
      'ownerLeaseId': 'owner',
      'usbLeaseId': 'exact-resource',
      'fd': 7,
      'serial': 'actual-serial',
    });
    final access = await permission;
    expect(access.fd, 7);
    expect(access.serial, 'actual-serial');
    await usb.cancel('attempt');
    await access.close();
    await access.close();
    expect(() => access.fd, throwsA(isA<RequestFailure>()));
    expect(cleanup, [
      {'attemptId': 'attempt', 'ownerLeaseId': 'owner'},
      {'usbLeaseId': 'exact-resource', 'ownerLeaseId': 'owner'},
    ]);
    await expectLater(
      usb.authorize(const UsbAuthorizationRequest(attemptId: 'late')),
      throwsA(isA<RequestFailure>()),
    );
  });

  test('其他代次的回执不能确认原资源已清理', () async {
    final usb = UsbAuthorization(
      ownerLeaseId: 'owner',
      isDisposed: () => false,
      request: (command, _) async => command == 'usb.authorize'
          ? {'ownerLeaseId': 'owner', 'usbLeaseId': 'exact-resource', 'fd': 7}
          : {'ownerLeaseId': 'successor', 'released': true},
    );
    final access = await usb.authorize(
      const UsbAuthorizationRequest(attemptId: 'attempt'),
    );
    await expectLater(
      access.close(),
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'usb_cleanup_unconfirmed',
        ),
      ),
    );
  });

  test('并发关闭等待原回执，失败后只重试原租约，不重放授权', () async {
    var authorizations = 0;
    final releases = <Json>[];
    final releasing = Completer<Json?>();
    var retryAllowed = false;
    final usb = UsbAuthorization(
      ownerLeaseId: 'original-owner',
      isDisposed: () => false,
      request: (command, params) async {
        if (command == 'usb.authorize') {
          authorizations++;
          return {
            'ownerLeaseId': 'original-owner',
            'usbLeaseId': 'original-resource',
            'fd': 7,
          };
        }
        expect(command, 'usb.release');
        releases.add(params);
        if (!retryAllowed) return releasing.future;
        return {'ownerLeaseId': 'original-owner', 'released': true};
      },
    );
    final access = await usb.authorize(
      const UsbAuthorizationRequest(attemptId: 'attempt'),
    );
    final first = access.close();
    final concurrent = access.close();
    expect(concurrent, same(first));
    expect(releases, hasLength(1));
    final failed = expectLater(
      first,
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'usb_cleanup_unconfirmed',
        ),
      ),
    );
    releasing.complete({'ownerLeaseId': 'original-owner', 'released': false});
    await failed;
    expect(() => access.fd, throwsA(isA<RequestFailure>()));
    retryAllowed = true;
    await access.close();
    await access.close();
    expect(authorizations, 1);
    expect(
      releases,
      List.filled(2, {
        'ownerLeaseId': 'original-owner',
        'usbLeaseId': 'original-resource',
      }),
    );
  });

  for (final malformed in [
    {'fd': 'invalid', 'usbLeaseId': 'exact-resource'},
    {'fd': 7, 'usbLeaseId': 'exact-resource', 'serial': 123},
    {'fd': 7},
  ]) {
    test('无效 USB 回执仍保留原资源清理权 $malformed', () async {
      final commands = <String>[];
      final cleanup = <Json>[];
      final usb = UsbAuthorization(
        ownerLeaseId: 'owner',
        isDisposed: () => false,
        request: (command, params) async {
          commands.add(command);
          if (command == 'usb.authorize') {
            return {'ownerLeaseId': 'owner', ...malformed};
          }
          cleanup.add(params);
          return {'ownerLeaseId': 'owner', 'released': true, 'cancelled': true};
        },
      );
      final access = await usb.authorize(
        const UsbAuthorizationRequest(attemptId: 'attempt'),
      );
      expect(() {
        access.fd;
        access.serial;
      }, throwsA(isA<RequestFailure>()));
      await access.close();
      expect(commands, [
        'usb.authorize',
        malformed.containsKey('usbLeaseId') ? 'usb.release' : 'usb.cancel',
      ]);
      expect(cleanup, [
        {
          'ownerLeaseId': 'owner',
          if (malformed.containsKey('usbLeaseId'))
            'usbLeaseId': 'exact-resource'
          else
            'attemptId': 'attempt',
        },
      ]);
    });
  }
}
