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
        if (command == 'usb.authorize') return authorized.future;
        cleanup.add(params);
        return {'ownerLeaseId': 'owner', 'cancelled': true, 'released': true};
      },
    );
    final permission = usb.authorize({'attemptId': 'attempt'});
    disposed = true;
    authorized.complete({'ownerLeaseId': 'owner', 'token': 'exact-resource'});
    expect((await permission)['token'], 'exact-resource');
    await usb.cancel({'attemptId': 'attempt'});
    await usb.release({'token': 'exact-resource'});
    expect(cleanup, [
      {'attemptId': 'attempt', 'ownerLeaseId': 'owner'},
      {'token': 'exact-resource', 'ownerLeaseId': 'owner'},
    ]);
    await expectLater(usb.authorize({}), throwsA(isA<RequestFailure>()));
  });

  test('其他代次的回执不能确认原资源已清理', () async {
    final usb = UsbAuthorization(
      ownerLeaseId: 'owner',
      isDisposed: () => true,
      request: (_, _) async => {'ownerLeaseId': 'successor', 'released': true},
    );
    await expectLater(
      usb.release({'token': 'exact-resource'}),
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'usb_cleanup_unconfirmed',
        ),
      ),
    );
  });
}
