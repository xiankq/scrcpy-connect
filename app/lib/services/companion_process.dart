import 'package:scrcpy_connect/utils/shell_quote.dart';
import 'package:scrcpy_connect/models/companion_exception.dart';
import 'package:scrcpy_connect/services/device_connection.dart';
import 'package:scrcpy_connect/services/companion_deployment_identity.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';

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
    'rm -f -- ${shellQuote(identity.jarPath)} && print -r -- removed',
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
CLASSPATH=${shellQuote(jar)} exec app_process / --nice-name=${shellQuote(nice)} com.interop.companion.Main ${shellQuote(socket)} ${shellQuote(token)}
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
rm -f -- ${shellQuote(jar)}
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
