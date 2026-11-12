/// 可交给应用恢复记录的精确部署身份；不保存认证 token 或产品设备 ID。
final class CompanionDeploymentIdentity {
  CompanionDeploymentIdentity({
    required this.pid,
    required this.started,
    required this.jarPath,
  }) {
    if (pid <= 1 ||
        started <= 0 ||
        !RegExp(r'^/data/local/tmp/interop-companion-[0-9a-f]{32}\.jar$')
            .hasMatch(jarPath)) {
      throw ArgumentError('互联服务部署身份无效。');
    }
  }
  final int pid;
  final int started;
  final String jarPath;
  String get niceName => 'interop.companion:$jarPath';
  Map<String, Object?> toJson() => {
    'pid': pid,
    'started': started,
    'jarPath': jarPath,
  };
  factory CompanionDeploymentIdentity.fromJson(Map<String, Object?> value) {
    if (value['pid'] is! int ||
        value['started'] is! int ||
        value['jarPath'] is! String) {
      throw const FormatException('互联服务部署身份格式无效。');
    }
    return CompanionDeploymentIdentity(
      pid: value['pid'] as int,
      started: value['started'] as int,
      jarPath: value['jarPath'] as String,
    );
  }
}
