import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

void main() {
  const fallback = '无法读取手机相册。请检查连接后重试。';

  test('未知失败和旧记录使用当前操作的提示', () {
    for (final error in [
      StateError('SocketException on /private/album'),
      const FormatException('Unexpected token'),
      '旧设备上 /private/album 的原始失败信息',
      PlatformException(code: 'internal', message: '无法读取 /private/album'),
    ]) {
      expect(failureMessage(error, fallback: fallback), fallback);
    }
  });

  test('用稳定的错误代码说明可采取的下一步', () {
    expect(
      failureMessage(
        const RequestFailure('disconnected', 'transport fd 17 closed'),
        fallback: fallback,
      ),
      '手机连接已断开。重新连接后再试。',
    );
    expect(
      failureMessage(
        PlatformException(code: 'storage_full'),
        fallback: fallback,
      ),
      '本机存储空间不足。腾出空间后再试。',
    );
  });

  test('写入和取消结果未知时先查看结果', () {
    expect(
      failureCodeMessage('result_unknown', fallback: fallback),
      '暂时无法确认操作是否完成。请先检查结果，再决定是否重试。',
    );
  });
}
