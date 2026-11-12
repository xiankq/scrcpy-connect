import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/display_recovery.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

void main() {
  test('退休没有显示恢复责任的连接不查询 SDK 或创建命令', () async {
    final recovery = DisplayRecovery(timeout: const Duration(seconds: 1));
    await recovery.retireConnection(
      DeviceConnection(client: _UnusedClient(), device: _device),
    );
    await recovery.close();
  });

  test('断开连接的显示流释放失败保留原句柄，重试不恢复或确认远端', () async {
    final api = _DisplayApi();
    final client = _Client(api);
    final connection = DeviceConnection(client: client, device: _device);
    final recovery = DisplayRecovery(timeout: const Duration(seconds: 1));
    addTearDown(() async {
      api.releaseAllowed = true;
      await recovery.retireConnection(connection);
      await client.services.close();
    });
    await expectLater(
      recovery.recover(connection),
      throwsA(isA<RequestFailure>()),
    );
    expect(api.commands, 1);
    expect(api.cancellations, isNotEmpty);
    await expectLater(
      recovery.retireConnection(connection),
      throwsA(isA<RequestFailure>()),
    );
    expect(api.commands, 1);
    expect(api.factsRead, ['old-connection']);
    expect(
      api.cancellations.every((id) => id == 'original-display-command'),
      isTrue,
    );

    api.releaseAllowed = true;
    await recovery.retireConnection(connection);
    expect(api.commands, 1);
    expect(api.factsRead, ['old-connection', 'old-connection']);
    final cancellations = api.cancellations.length;
    await recovery.retireConnection(connection);
    await recovery.close();
    expect(api.cancellations, hasLength(cancellations));
    expect(api.factsRead, hasLength(2));
  });
}

const _device = AdbDevice(
  id: 'old-connection',
  serial: 'serial',
  state: 'device',
);

class _DisplayApi implements NativeAdbApi {
  var releaseAllowed = false;
  var commands = 0;
  final cancellations = <String>[];
  final factsRead = <String>[];
  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(id, 'old-connection');
    commands++;
    return 'original-display-command';
  }

  @override
  Future<NativeAdbEvent?> next(String operationId) async =>
      throw const AdbException('disconnected');
  @override
  Future<void> write(String id, AdbServiceInput input) async =>
      throw const AdbException('disconnected');
  @override
  Future<void> cancel(String operationId) async {
    cancellations.add(operationId);
    if (!releaseAllowed) throw StateError('display stream release unconfirmed');
  }

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    factsRead.add(id);
    return const AdbConnectionFacts(
      officialServer: false,
      closed: true,
      features: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应调用其他原生操作：${invocation.memberName}');
}

class _Client implements AdbClient {
  _Client(NativeAdbApi api)
    : services = AdbServices(() => api, (device) async => device, () {});
  @override
  final AdbServices services;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应修改设备连接：${invocation.memberName}');
}

class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('没有恢复责任：${invocation.memberName}');
}
