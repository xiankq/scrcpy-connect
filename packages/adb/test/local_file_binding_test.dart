import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:adb/src/native/frb_native_adb_api.dart';
import 'package:adb/src/native/generated/frb_generated.dart';
import 'package:adb/src/native/generated/third_party/interop_adb_api/api.dart'
    as native;
import 'package:flutter_test/flutter_test.dart';

native.AdbFileExecutionEvent errorEvent(String code) =>
    native.AdbFileExecutionEvent(
      kind: 'error',
      entries: const [],
      transferred: BigInt.zero,
      truncated: false,
      errorCode: code,
      errorMessage: 'permission_denied: 这只是原样展示消息',
      errno: 2,
    );

final class LocalApi implements AdbRustLibApi {
  @override
  Future<native.AdbFileExecutionEvent> interopAdbApiApiAdbLocalFileStat({
    required List<int> path,
  }) async => errorEvent('not_found');
  @override
  Future<native.AdbFileExecutionEvent> interopAdbApiApiAdbLocalFileList({
    required List<int> path,
    required int limit,
  }) async => errorEvent('permission_denied');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => AdbRustLib.initMock(api: LocalApi()));
  tearDown(AdbRustLib.dispose);
  test('local stat control flow uses typed error code and leaves message untouched', () async {
    await expectLater(
      const FrbNativeAdbApi().localFileStat(Uint8List.fromList([47, 255])),
      throwsA(
        isA<AdbException>()
            .having((e) => e.code, 'code', 'not_found')
            .having(
              (e) => e.message,
              'message',
              'permission_denied: 这只是原样展示消息',
            ),
      ),
    );
  });
  test(
    'local directory permission failure is not an empty successful listing',
    () async {
      await expectLater(
        const FrbNativeAdbApi().localFileList(Uint8List.fromList([47]), 10),
        throwsA(
          isA<AdbException>().having(
            (e) => e.code,
            'code',
            'permission_denied',
          ),
        ),
      );
    },
  );
}
