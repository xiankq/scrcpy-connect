import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  test('scrcpy 配套 FRB 支持独立准入 scope，旧关闭不撤销新权限', () async {
    final api = await createNativeScrcpyAdbApi() as NativeAdbAdmissionApi;
    final first = await api.attachAdmissionScope('paired-sdk-loader');
    addTearDown(() => api.closeAdmissionScope(first.scopeId));
    final next = await api.attachAdmissionScope(
      first.scopeKey,
      expectedScopeId: first.scopeId,
    );
    addTearDown(() => api.closeAdmissionScope(next.scopeId));
    await api.closeAdmissionScope(first.scopeId);
    expect(
      (await api.inspectAdmissionScope(next.scopeKey))!.scopeId,
      next.scopeId,
    );
    final handshake = await api.createScopedHandshake(next.scopeId);
    await (api as NativeAdbHandshakeApi).closeHandshake(handshake);
    await api.closeAdmissionScope(next.scopeId);
    expect(await api.inspectAdmissionScope(next.scopeKey), isNull);
  });
  test('默认 Native Assets 加载精确 scrcpy 库并收到真实参数校验错误', () async {
    // 空输入在原生端校验失败，不登记测试服务器，也不创建连接或远端捕获。
    Future<void> rejectEmptyServer() => expectLater(
      initializeNativeScrcpy(serverBytes: Uint8List(0)),
      throwsA(
        isA<ScrcpyException>().having(
          (error) => error.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
    await Future.wait([rejectEmptyServer(), rejectEmptyServer()]);
    await rejectEmptyServer();
  });
}
