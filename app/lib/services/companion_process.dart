import 'package:scrcpy_connect/services/companion_protocol.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

String companionQuote(String value) {
  if (value.contains('\u0000')) throw ArgumentError('shell 参数不能包含 NUL。');
  return "'${value.replaceAll("'", "'\\''")}'";
}

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
[ "\$cmd" = ${companionQuote(niceName)} ] || { print -r -- identity-mismatch; exit 41; }
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

Future<String> companionShell(
  DeviceConnection connection,
  String command, {
  required Duration timeout,
  AdbCancellation? cancellation,
}) async {
  final output = BytesBuilder(copy: false);
  await for (final event in connection.client.shell(
    connection.device,
    command,
    timeout: timeout,
    cancellation: cancellation,
  )) {
    if (event.channel == AdbShellChannel.exit) {
      if (event.exitCode != null && event.exitCode != 0) {
        throw CompanionException(
          'remote_process_error',
          '远端检查失败：${event.exitCode}。',
        );
      }
    } else {
      if (output.length + event.bytes.length > 8192) {
        throw const CompanionException('output_limit', '远端检查输出超过限制。');
      }
      output.add(event.bytes);
    }
  }
  return utf8.decode(output.takeBytes());
}

/// 只确认此主进程退出；不能代替它曾创建的媒体子进程退出回执。
Future<void> stopCompanionProcess(
  DeviceConnection connection,
  CompanionDeploymentIdentity identity, {
  required Duration timeout,
}) async {
  final signal = await companionShell(
    connection,
    identity.terminateCommand,
    timeout: timeout,
  );
  if (!signal.startsWith('released:') && signal.trim() != 'signalled') {
    throw const CompanionException('process_identity', '原互联服务身份未能确认，未继续清理。');
  }
  final exited = await companionShell(
    connection,
    identity.waitCommand,
    timeout: timeout,
  );
  if (!exited.startsWith('released:')) {
    throw const CompanionException('cleanup_unconfirmed', '尚未确认原互联服务退出。');
  }
}

/// 恢复只回收明确记录的原进程；不重新执行业务动作，也不停止共享设备连接。
Future<void> cleanupCompanionDeployment(
  DeviceConnection connection,
  CompanionDeploymentIdentity identity, {
  required Duration timeout,
}) async {
  await stopCompanionProcess(connection, identity, timeout: timeout);
  final removed = await companionShell(
    connection,
    'rm -f -- ${companionQuote(identity.jarPath)} && print -r -- removed',
    timeout: timeout,
  );
  if (removed.trim() != 'removed') {
    throw const CompanionException('cleanup_unconfirmed', '互联服务部署文件尚未确认删除。');
  }
}

/// 原始 ADB stdin 专属于监督器；Java 不继承它。EOF 后先回收原任务再删除 JAR。
String companionLaunchCommand(String jar, String socket, String token) {
  final nice = 'interop.companion:$jar';
  return '''
run_owned() {
IFS= read -r own_stat < /proc/self/stat || exit 40
own_pid=\${own_stat%% *}
case "\$own_pid" in ''|*[!0-9]*) exit 40 ;; esac
kill -STOP "\$own_pid" || exit 40
CLASSPATH=${companionQuote(jar)} exec app_process / --nice-name=${companionQuote(nice)} com.interop.companion.Main ${companionQuote(socket)} ${companionQuote(token)}
}
cleanup() {
result=\$1
trap - EXIT
trap '' HUP INT TERM USR1
for job in %1 %2; do
jobs "\$job" >/dev/null 2>&1
kill -TERM "\$job" 2>/dev/null
kill -CONT "\$job" 2>/dev/null
done
if [ -n "\${child:-}" ]; then wait "\$child" 2>/dev/null; fi
if [ -n "\${watcher:-}" ]; then wait "\$watcher" 2>/dev/null; fi
rm -f -- ${companionQuote(jar)}
exit "\$result"
}
trap 'cleanup \$?' EXIT
trap 'cleanup 129' HUP USR1
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
watch_input() { while IFS= read -r keepalive; do :; done; kill -USR1 \$\$; }
exec 3<&0
watch_input <&3 &
watcher=\$!
exec 3<&-
run_owned </dev/null &
child=\$!
while :; do
IFS= read -r stat < /proc/\$child/stat || exit 40
rest=\${stat##*) }
set -- \$rest
state=\$1
shift 19 || exit 40
started=\$1
case "\$started" in ''|*[!0-9]*) exit 40 ;; esac
case "\$state" in T) break ;; Z|X|x) exit 40 ;; esac
done
print -r -- "__INTEROP_PID__\$child:\$started"
jobs %2 >/dev/null 2>&1
kill -CONT %2 2>/dev/null || exit 40
wait "\$child"
exit "\$?"
''';
}
