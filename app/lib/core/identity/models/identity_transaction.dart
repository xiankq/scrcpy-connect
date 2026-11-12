enum IdentityTransactionKind { key, useGlobal, retire }

/// 只记录一次未确认的本机身份提交或退休，不复制设备记录、私钥或原生句柄。
final class IdentityTransaction {
  IdentityTransaction({
    required this.kind,
    required Set<String> affected,
    required this.global,
    this.deviceId,
    this.previousFingerprint,
    this.fingerprint,
  }) : affected = Set.unmodifiable(affected);
  final IdentityTransactionKind kind;
  final Set<String> affected;
  final bool global;
  final String? deviceId, previousFingerprint, fingerprint;

  Map<String, Object?> toJson() => {
    'version': 1,
    'kind': kind.name,
    'affected': affected.toList(),
    'global': global,
    'deviceId': deviceId,
    'previousFingerprint': previousFingerprint,
    'fingerprint': fingerprint,
  };
}
