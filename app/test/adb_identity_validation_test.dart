import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/connection/adb_identity_validation.dart';

// 合成 DER 载荷仅检查文本包装，不验证密码学有效性。
const envelope =
    '-----BEGIN PRIVATE KEY-----\nMAMCAQA=\n-----END PRIVATE KEY-----';

void main() {
  test('PKCS1 and PKCS8 envelopes normalize BOM and line endings', () {
    expect(validateAdbPrivateKeyPem(envelope), isNull);
    expect(
      validateAdbPrivateKeyPem(
        envelope.replaceAll('PRIVATE KEY', 'RSA PRIVATE KEY'),
      ),
      isNull,
    );
    final windows = '\uFEFF${envelope.replaceAll('\n', '\r\n')}\r\n';
    expect(normalizeAdbPrivateKeyPem(windows), envelope);
    expect(decodeAdbPrivateKeyFile(utf8.encode(windows)), envelope);
    expect(validateAdbPrivateKeyPem(windows), isNull);
  });
  test('rejects missing or mismatched boundaries and noncanonical Base64', () {
    for (final invalid in [
      '',
      'password123',
      envelope.replaceFirst('END PRIVATE KEY', 'END RSA PRIVATE KEY'),
      envelope.replaceFirst('MAMCAQA=', ''),
      envelope.replaceFirst('MAMCAQA=', '***'),
      envelope.replaceFirst('MAMCAQA=', 'MAMCAQA'),
      envelope.replaceFirst('MAMCAQA=', 'MAMCAQB='),
      envelope.replaceFirst('MAMCAQA=', '中文'),
      '$envelope\n$envelope',
    ]) {
      expect(validateAdbPrivateKeyPem(invalid), isNotNull);
    }
    expect(
      validateAdbPrivateKeyPem(
        envelope.replaceAll('PRIVATE KEY', 'PUBLIC KEY'),
      ),
      '需要 PEM 私钥，不能使用公钥',
    );
    expect(
      validateAdbPrivateKeyPem(
        envelope.replaceAll('PRIVATE KEY', 'ENCRYPTED PRIVATE KEY'),
      ),
      '不支持加密私钥，请使用未加密的 PEM 私钥',
    );
    expect(
      validateAdbPrivateKeyPem(
        envelope.replaceFirst('MAMCAQA=', 'Proc-Type: 4,ENCRYPTED\nMAMCAQA='),
      ),
      '不支持加密私钥，请使用未加密的 PEM 私钥',
    );
  });
  test('text and file limits use bytes and reject binary or invalid UTF8', () {
    expect(
      validateAdbPrivateKeyPem('x' * (maxAdbPrivateKeyBytes + 1)),
      '私钥不能超过 32 KiB',
    );
    expect(
      validateAdbPrivateKeyPem('中' * (maxAdbPrivateKeyBytes ~/ 2)),
      '私钥不能超过 32 KiB',
    );
    expect(
      () => decodeAdbPrivateKeyFile(List.filled(maxAdbPrivateKeyBytes + 1, 65)),
      throwsA(isA<AdbPrivateKeyFileFailure>()),
    );
    expect(
      () => decodeAdbPrivateKeyFile([0xff, 0xfe]),
      throwsA(isA<AdbPrivateKeyFileFailure>()),
    );
    expect(
      () => decodeAdbPrivateKeyFile([0, 1]),
      throwsA(isA<AdbPrivateKeyFileFailure>()),
    );
  });
}
