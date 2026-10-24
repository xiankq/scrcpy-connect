part of 'api.dart';

/// 密钥的公开事实；指纹的算法与输入编码必须一起比较。
final class AdbIdentityInfo {
  const AdbIdentityInfo({
    required this.fingerprint,
    required this.fingerprintAlgorithm,
    required this.fingerprintInput,
    required this.bits,
    required this.exponent,
  });
  final String fingerprint, fingerprintAlgorithm, fingerprintInput;
  final int bits, exponent;
}

enum AdbIdentityCommitState { committed, unchanged, unknown }

/// unknown 表示发布结果或持久化未获确认，调用方必须重新核验，不能盲目重试。
final class AdbIdentityCommitReceipt {
  const AdbIdentityCommitReceipt({
    required this.state,
    this.identity,
    this.error,
  });
  final AdbIdentityCommitState state;
  final AdbIdentityInfo? identity;
  final String? error;
}

/// 通用 ADB 密钥能力，不决定产品使用哪个身份或哪些设备需要断开。
abstract interface class AdbIdentities {
  /// 原子创建缺失的身份，已有身份必须通过校验；不会覆盖旧密钥。
  Future<void> prepareIdentity(String path);

  /// 缺失返回 null；损坏、链接或权限不合要求均报错，不自动生成替代身份。
  Future<AdbIdentityInfo?> inspectIdentity(String path);
  Future<AdbIdentityInfo> validateIdentity(String pem);

  /// 不提供旧指纹时仅允许安装到空位置；提供时按旧指纹执行比较后替换。
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  });
}
