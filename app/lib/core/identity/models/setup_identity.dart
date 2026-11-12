/// null 表示沿用目标设备当前身份；显式选择仅用于尚未绑定的新设备。
sealed class SetupIdentity {
  const SetupIdentity();
  const factory SetupIdentity.global() = GlobalSetupIdentity;
  const factory SetupIdentity.dedicated(String privateKeyPem) =
      DedicatedSetupIdentity;
}

final class GlobalSetupIdentity extends SetupIdentity {
  const GlobalSetupIdentity();
}

/// 私钥仅属于本次设置输入，不进入设备投影或默认字符串输出。
final class DedicatedSetupIdentity extends SetupIdentity {
  const DedicatedSetupIdentity(this.privateKeyPem);
  final String privateKeyPem;
}
