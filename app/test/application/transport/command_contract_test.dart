import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/command_contract.dart';
import 'package:scrcpy_connect/application/transport/commands_generated.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

Matcher _failure(String code) => throwsA(
  isA<ApplicationCommandException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  test('命令结构在执行前校验名称、必填字段和可选字段', () {
    expect(
      () => validateCommandRequest('devices.lsit', {}),
      _failure('unknown_command'),
    );
    for (final value in [null, 1, '', 'a\u0000b']) {
      expect(
        () => validateCommandRequest('devices.connect', {'deviceId': value}),
        _failure('invalid_argument'),
      );
    }
    expect(
      () => validateCommandRequest('session.start', {
        'deviceId': 'a',
        'packageName': 7,
      }),
      _failure('invalid_argument'),
    );
    expect(
      validateCommandRequest('devices.connect', {'deviceId': 'a'}),
      ApplicationCommand.devicesConnect,
    );
    expect(
      validateCommandRequest('transfers.cancel', {'batchId': 'batch'}),
      ApplicationCommand.transfersCancel,
    );
    expect(
      validateCommandRequest('transfers.cancel', {'transferId': 'item'}),
      ApplicationCommand.transfersCancel,
    );
  });

  test('应用自有命令也使用同一结构契约，不以历史原生归属决定授权', () {
    expect(
      validateCommandRequest('documents.importFiles', {}),
      ApplicationCommand.documentsImportFiles,
    );
    expect(
      validateCommandRequest('sharing.pending', {}),
      ApplicationCommand.sharingPending,
    );
  });

  test('结果缺字段或字段类型错误不能变成空成功', () {
    for (final result in <Map<String, dynamic>>[
      {},
      {'device': <Object?>[]},
      {'devices': 'invalid'},
    ]) {
      expect(
        () => validateCommandResult(ApplicationCommand.devicesList, result),
        _failure('invalid_response'),
      );
    }
    expect(
      () => validateCommandResult(ApplicationCommand.devicesList, {
        'devices': <Object?>[],
      }),
      returnsNormally,
    );
    expect(
      () => validateCommandResult(ApplicationCommand.transfersList, {}),
      _failure('invalid_response'),
    );
    expect(
      () => validateCommandResult(ApplicationCommand.transfersList, {
        'transfers': <Object?>[],
      }),
      returnsNormally,
    );
    expect(
      () => validateCommandResult(ApplicationCommand.transfersList, {
        'transfers': 'invalid',
      }),
      _failure('invalid_response'),
    );
  });

  test('组合快照必须已具备全部公开投影，契约不会补造业务状态', () {
    final complete = <String, dynamic>{
      'sequence': 1,
      'settings': <String, dynamic>{},
      for (final name in [
        'devices',
        'sessions',
        'sources',
        'transfers',
        'activities',
        'shares',
        'companions',
        'observations',
      ])
        name: <Object?>[],
    };
    expect(
      () => validateCommandResult(ApplicationCommand.stateSnapshot, complete),
      returnsNormally,
    );
    for (final key in complete.keys) {
      final incomplete = Map<String, dynamic>.of(complete)..remove(key);
      expect(
        () =>
            validateCommandResult(ApplicationCommand.stateSnapshot, incomplete),
        _failure('invalid_response'),
        reason: '缺少$key必须由实际所有者补齐',
      );
    }
  });

  test('数值类型拒绝非有限值', () {
    expect(
      () => validateCommandRequest('session.touch', {
        'captureGeneration': 1,
        'pressure': double.nan,
      }),
      _failure('invalid_argument'),
    );
    expect(
      validateCommandRequest('session.touch', {
        'captureGeneration': 1,
        'pressure': 0.5,
      }),
      ApplicationCommand.sessionTouch,
    );
  });
}
