import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('独立 SDK 加载自己的桥接并保留持久身份', () async {
    final directory = await Directory.systemTemp.createTemp(
      'adb-sdk-identity-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final identity = File(p.join(directory.path, 'identity.pem'));

    final api = await createNativeAdbApi();
    expect(await api.devices(), isEmpty);
    await prepareAdbIdentity(identity.path);
    final original = await identity.readAsBytes();
    expect(original, isNotEmpty);
    await prepareAdbIdentity(identity.path);
    expect(await identity.readAsBytes(), original);
    if (!Platform.isWindows) {
      expect((await identity.stat()).mode & 0x1ff, 0x180);
    }

    await identity.writeAsString('损坏的身份');
    await expectLater(
      prepareAdbIdentity(identity.path),
      throwsA(isA<AdbException>()),
    );
    expect(await identity.readAsString(), '损坏的身份');
  });
}
