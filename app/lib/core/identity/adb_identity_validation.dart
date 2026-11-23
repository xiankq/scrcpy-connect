import 'package:scrcpy_connect/core/identity/adb_private_key_file_failure.dart';

import 'dart:convert';

const maxAdbPrivateKeyBytes = 32 * 1024;

String normalizeAdbPrivateKeyPem(String input) => input
    .replaceFirst(RegExp(r'^\uFEFF'), '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .trim();

/// 此处只验证 PEM 包装与规范 Base64；替换身份前由后端验证 RSA 结构、位数和指数。
String? validateAdbPrivateKeyPem(String? input) {
  final raw = input ?? '';
  if (raw.length > maxAdbPrivateKeyBytes ||
      utf8.encode(raw).length > maxAdbPrivateKeyBytes) {
    return '私钥不能超过 32 KiB';
  }
  final text = normalizeAdbPrivateKeyPem(raw);
  if (text.isEmpty) return '请输入 PEM 私钥';
  if (text.contains('ENCRYPTED PRIVATE KEY') ||
      text.contains('Proc-Type: 4,ENCRYPTED')) {
    return '不支持加密私钥，请使用未加密的 PEM 私钥';
  }
  if (text.contains('PUBLIC KEY-----')) return '需要 PEM 私钥，不能使用公钥';
  final match = RegExp(
    r'^-----BEGIN (RSA PRIVATE KEY|PRIVATE KEY)-----\n([A-Za-z0-9+/= \t\n]+)\n-----END \1-----$',
  ).firstMatch(text);
  if (match == null) return 'PEM 私钥格式无效';
  final payload = match.group(2)!.replaceAll(RegExp(r'[ \t\n]'), '');
  if (payload.isEmpty ||
      !RegExp(
        r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
      ).hasMatch(payload)) {
    return 'PEM 私钥格式无效';
  }
  try {
    final bytes = base64.decode(payload);
    if (bytes.isEmpty || base64.encode(bytes) != payload) return 'PEM 私钥格式无效';
  } on FormatException {
    return 'PEM 私钥格式无效';
  }
  return null;
}

String decodeAdbPrivateKeyFile(List<int> bytes) {
  if (bytes.length > maxAdbPrivateKeyBytes) {
    throw const AdbPrivateKeyFileFailure('私钥文件不能超过 32 KiB。');
  }
  try {
    final text = utf8.decode(bytes);
    if (text.codeUnits.any(
      (c) => c < 32 && c != 9 && c != 10 && c != 13 || c == 127,
    )) {
      throw const FormatException();
    }
    return normalizeAdbPrivateKeyPem(text);
  } on FormatException {
    throw const AdbPrivateKeyFileFailure('无法读取这个密钥文件。请选择 PEM 格式的私钥文件。');
  }
}
