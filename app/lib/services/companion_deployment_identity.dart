import 'package:scrcpy_connect/utils/shell_quote.dart';

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

  String get _readIdentity =>
      '''
p=$pid
expected=$started
if [ ! -e /proc/\$p ]; then print -r -- released:absent; exit 0; fi
IFS= read -r stat < /proc/\$p/stat || exit 42
rest=\${stat##*) }
set -- \$rest
state=\$1
shift 19 || exit 42
case "\$1" in ''|*[!0-9]*) exit 42 ;; esac
if [ "\$1" != "\$expected" ]; then print -r -- released:replaced; exit 0; fi
case "\$state" in Z|X|x) print -r -- released:exited; exit 0 ;; esac
''';

  /// 检查与发信号在同一 shell 中完成；不按名称搜索其他部署。
  String get terminateCommand =>
      '''
$_readIdentity
IFS= read -r -d '' cmd < /proc/\$p/cmdline || exit 42
[ "\$cmd" = ${shellQuote(niceName)} ] || { print -r -- identity-mismatch; exit 41; }
kill -TERM "\$p" || exit 42
print -r -- signalled
''';
  String get waitCommand =>
      '''
while :; do
$_readIdentity
sleep 0.02 || exit 42
done
''';
}
