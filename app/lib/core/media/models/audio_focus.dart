enum AudioFocusSignal { none, granted, transientLoss, permanentLoss, noisy }

/// 申请回执保留未核验的代次，输出所有者负责拒绝旧代并排空迟到租约。
final class AudioFocusResult {
  const AudioFocusResult({required this.granted, this.epoch});
  final bool granted;
  final int? epoch;
}
