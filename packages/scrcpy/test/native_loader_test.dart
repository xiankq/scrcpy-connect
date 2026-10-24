import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';

void main() {
  test('公开配套ADB接口稳定指向同scrcpy宿主并提供精确认领能力', () async {
    final api = await createNativeScrcpyAdbApi();
    expect(identical(api, await createNativeScrcpyAdbApi()), isTrue);
    expect(api, isA<NativeAdbConnectionApi>());
    expect(api, isA<NativeAdbAdmissionApi>());
    expect(api, isA<NativeAdbServerApi>());
    // 只枚举真实注册表，不按序列号创建替代连接。
    expect(await api.devices(), isA<List<AdbDevice>>());
    expect(await listNativeScrcpyServers(), isA<List<AdbServerInfo>>());
  });
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
