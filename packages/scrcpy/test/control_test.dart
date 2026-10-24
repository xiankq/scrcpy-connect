import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy/src/native/frb_native_scrcpy_api.dart';

void main() {
  test('调整显示尺寸在FRB窄化前拒绝零、负数及超出u16范围的值', () async {
    const api = FrbNativeScrcpyApi();
    for (final (width, height) in [
      (0, 600),
      (800, 0),
      (-1, 600),
      (800, -1),
      (65536, 600),
      (800, 65536),
      (0x100000001, 600),
    ]) {
      // 不初始化原生库；这些输入必须在任何 FFI 调用之前被拒绝。
      await expectLater(
        api.sendControl(
          'capture',
          ScrcpyResizeDisplay(width: width, height: height),
        ),
        throwsA(
          isA<ScrcpyException>().having(
            (error) => error.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
    }
  });
}
