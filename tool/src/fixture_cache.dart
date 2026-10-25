import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// 产物只在源码、工具链及签名身份全部相同时复用。
Future<String> fixtureFingerprint(
  Map<String, File> inputs,
  List<String> toolVersions,
) async {
  final names = inputs.keys.toList()..sort();
  final values = <String, String>{};
  for (final name in names) {
    values[name] = await _digest(inputs[name]!);
  }
  return sha256
      .convert(utf8.encode(jsonEncode([1, values, toolVersions])))
      .toString();
}

Future<bool> canReuseFixture(
  File apk,
  File receipt,
  String fingerprint,
  Future<void> Function() verifySignature,
) async {
  if (!await apk.exists() || !await receipt.exists()) return false;
  try {
    final previous = jsonDecode(await receipt.readAsString());
    if (previous is! Map ||
        previous['inputs'] != fingerprint ||
        previous['apkSha256'] != await _digest(apk)) {
      return false;
    }
    await verifySignature();
    return true;
  } on Exception {
    // 清单、APK 或签名受损只能重建，不能成为一次成功的缓存命中。
    return false;
  }
}

Future<void> recordFixture(File apk, File receipt, String fingerprint) async {
  await receipt.writeAsString(
    jsonEncode({'inputs': fingerprint, 'apkSha256': await _digest(apk)}),
  );
}
