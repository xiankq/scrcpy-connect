import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

String _quote(String value) {
  if (value.contains('\x00')) throw ArgumentError('Shell 参数不能包含 NUL。');
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _nonce() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

Never _fail(String code, String message) =>
    throw ApplicationCommandException(code, message);

/// 固定 scrcpy 清单查询的执行结果；退出码来自监督器对原查询子进程的 wait。
final class ScrcpyQueryResult {
  ScrcpyQueryResult(this.stdout, this.exitCode);
  final Uint8List stdout;
  final int exitCode;
}

/// 一个临时清单进程及其精确 ADB 流；不拥有设备连接或上传文件。
/// START 前不创建子进程，取得停止态 PID/start 后才发送 RUN。close 经原监督流
/// 终止并等待同一子进程；断流后只读取退出事实，不按裸 PID 发送信号。
final class ScrcpyQueryProcess {
  ScrcpyQueryProcess({
    required this.connection,
    required this.jarPath,
    required this.option,
    required this.maxBytes,
    required this.timeout,
  }) {
    if (!RegExp(
          r'^/data/local/tmp/interop-(?:encoders|apps)-[A-Za-z0-9-]+\.jar$',
        ).hasMatch(jarPath) ||
        !const {'list_encoders', 'list_apps'}.contains(option) ||
        maxBytes <= 0) {
      throw ArgumentError('清单查询参数无效。');
    }
    adbTimeoutMillis(timeout);
  }

  final DeviceConnection connection;
  final String jarPath, option;
  final int maxBytes;
  final Duration timeout;
  final _token = _nonce();
  final _stop = AdbCancellation();
  final _ready = Completer<void>();
  final _checks = <AdbServiceSession>{};
  final _writes = <Future<void>>{};
  final _output = BytesBuilder(copy: false);
  final _line = <int>[];
  Future<void>? _opening, _reading, _closing;
  Future<ScrcpyQueryResult>? _running;
  AdbServiceSession? _session;
  int? _pid, _started, _exitCode;
  ({ApplicationCommandException error, StackTrace stack})? _protocolFailure;
  int _lineBytes = 0, _bytes = 0, _contentBytes = 0;
  bool _startAttempted = false, _closed = false, _released = false;
  bool _lineOverflow = false, _timedOut = false, _tooLarge = false;
  bool _processReleased = false;

  String get _nice => 'interop.query:$jarPath';
  String get _readyPrefix => '__INTEROP_QUERY_READY_${_token}__:';
  String get _endPrefix => '__INTEROP_QUERY_END_${_token}__:';

  Future<ScrcpyQueryResult> run(AdbCancellation cancellation) {
    if (_closed) _fail('cancelled', '清单查询已停止准入。');
    return _running ??= _run(cancellation);
  }

  Future<ScrcpyQueryResult> _run(AdbCancellation cancellation) async {
    cancellation.check();
    _ready.future.ignore();
    final unlisten = cancellation.onCancel(_stop.cancel);
    final timer = Timer(timeout, () {
      _timedOut = true;
      _stop.cancel();
    });
    try {
      // 创建不可丢弃：先保存迟到句柄，不能把取消令牌传给会隐藏迟到句柄的创建入口。
      await (_opening = _open());
      _check();
      // START 写入可能迟到交付；先登记责任，再允许远端创建停止态子进程。
      _startAttempted = true;
      final starting = _write('START');
      await Future.any([starting, _stop.whenCancelled]);
      _check();
      await Future.any([_ready.future, _stop.whenCancelled]);
      _check();
      final writing = _write('RUN');
      await Future.any([writing, _stop.whenCancelled]);
      if (_stop.isCancelled) {
        // 取消不能丢弃仍在写入 RUN 的本机任务；先回收原进程和流，再等待写入实际退出。
        try {
          await close();
        } finally {
          await writing.then<void>((_) {}, onError: (Object _) {});
        }
      }
      _check();
      await Future.any([_reading!, _stop.whenCancelled]);
      _check();
      if (_exitCode == null) _fail('result_unknown', '清单查询缺少监督终态。');
      if (_contentBytes > maxBytes || _tooLarge) {
        _fail('byte_limit', '设备查询输出超过本次限额。');
      }
      return ScrcpyQueryResult(
        Uint8List.fromList(_output.takeBytes().take(_contentBytes).toList()),
        _exitCode!,
      );
    } finally {
      timer.cancel();
      unlisten();
    }
  }

  void _check() {
    if (_protocolFailure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
    if (_tooLarge) _fail('byte_limit', '设备查询输出超过本次限额。');
    if (_timedOut) _fail('timeout', '设备清单查询超时。');
    if (_closed || _stop.isCancelled) _fail('cancelled', '设备清单查询已取消。');
  }

  Future<void> _open() async {
    _session = await connection.client.services.exec(
      connection.device,
      _launch,
      // 业务期限由本对象撤销；留出清理时间，读取不能先于监督终态被期限丢弃。
      timeout: timeout + const Duration(seconds: 10),
    );
    _reading = _read();
    _reading!.ignore();
  }

  Future<void> _read() async {
    try {
      await for (final event in _session!.events) {
        for (final byte in event.bytes) {
          if (_pid != null) {
            _bytes++;
            if (_output.length < maxBytes + 512) _output.addByte(byte);
          }
          _lineBytes++;
          if (_line.length < 256) {
            _line.add(byte);
          } else {
            _lineOverflow = true;
          }
          if (byte == 10) {
            try {
              _acceptLine();
            } on ApplicationCommandException catch (error, stack) {
              // 诊断或坏帧阻止查询交付，但不能切断随后真实的监督退出证明。
              _protocolFailure ??= (error: error, stack: stack);
              if (!_ready.isCompleted) _ready.completeError(error, stack);
              _stop.cancel();
            }
            _line.clear();
            _lineBytes = 0;
            _lineOverflow = false;
          }
          // 额外空间只用于扫描有界监督帧；任意长输出不会无限缓存。
          if (_bytes > maxBytes + 512 && !_tooLarge) {
            _tooLarge = true;
            _stop.cancel();
          }
        }
      }
      if (_protocolFailure case final failure?) {
        Error.throwWithStackTrace(failure.error, failure.stack);
      }
      if (_exitCode == null) _fail('result_unknown', '清单查询未返回完整监督终态。');
    } catch (error, stack) {
      if (!_ready.isCompleted) _ready.completeError(error, stack);
      rethrow;
    }
  }

  void _acceptLine() {
    final line = _lineOverflow
        ? ''
        : ascii.decode(_line, allowInvalid: true).trim();
    // 监督终态自带一个前导换行；READY 前失败也必须能读取随后完整的 END。
    if (_pid == null && line.isEmpty) return;
    if (_pid == null && !line.startsWith(_endPrefix)) {
      final ready = RegExp('^${RegExp.escape(_readyPrefix)}([0-9]+):([0-9]+)\$')
          .firstMatch(line);
      if (ready == null) _fail('process_identity', '查询启动身份缺失或不完整。');
      final pid = int.tryParse(ready[1]!);
      final started = int.tryParse(ready[2]!);
      if (pid == null || pid <= 1 || started == null || started <= 0) {
        _fail('process_identity', '查询启动身份无效。');
      }
      _pid = pid;
      _started = started;
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    if (!line.startsWith(_endPrefix)) return;
    if (!_startAttempted) _fail('invalid_data', '未授权启动返回了监督终态。');
    final result = int.tryParse(line.substring(_endPrefix.length));
    if (_exitCode != null || result == null || result < 0 || result > 255) {
      _fail('invalid_data', '查询监督终态无效或重复。');
    }
    // 监督器在终态前额外写一个换行，不能将控制帧计入实际输出限额。
    _contentBytes = _pid == null ? 0 : _bytes - _lineBytes - 1;
    if (_contentBytes < 0) _fail('invalid_data', '查询监督终态边界无效。');
    _exitCode = result;
    _processReleased = true;
    if (!_ready.isCompleted) {
      _ready.completeError(
        const ApplicationCommandException('process_identity', '查询在取得启动身份前已退出。'),
      );
    }
  }

  /// 清理失败保留原进程与原流，下次只核验/回收，不重放清单查询。
  Future<void> close() {
    if (_released) return Future.value();
    _closed = true;
    _stop.cancel();
    return _closing ??= _close().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _write(String verb) {
    final writing = _session!.write(
      Uint8List.fromList(utf8.encode('$verb $_token\n')),
    );
    _writes.add(writing);
    writing.then<void>(
      (_) {
        _writes.remove(writing);
      },
      onError: (Object _) {
        _writes.remove(writing);
      },
    );
    return writing;
  }

  Future<void> _releaseStream() async {
    if (_session case final session?) {
      await session.close();
      _session = null;
    }
    // 原流实际关闭后，写入和读取任务仍必须完整收敛。
    await Future.wait(
      _writes.toList().map(
        (writing) => writing.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    await _reading?.then<void>((_) {}, onError: (Object _) {});
  }

  Future<void> _close() async {
    await _opening?.then<void>((_) {}, onError: (Object _) {});
    for (final check in _checks.toList()) {
      await check.close();
      _checks.remove(check);
    }
    if (_startAttempted && !_processReleased && _session != null) {
      try {
        // 只有原监督器持有 job 身份，不能先检查 /proc 再按裸 PID kill。
        await _write('STOP').timeout(timeout);
      } catch (_) {
        // STOP 写入可能在对端已经退出时失败，仍须排空其已在途的 END。
      }
      try {
        await _reading!.timeout(timeout);
      } catch (_) {
        // 读取错误不提供退出证明；关流后再只读核验。
      }
    }
    await _releaseStream();
    if (_startAttempted && !_processReleased && _pid != null) {
      final waited = await _inspect('''
while :; do
$_identity
sleep 0.02 || exit 42
done
''');
      if (!const {
        'released:absent\n',
        'released:replaced\n',
        'released:exited\n',
      }.contains(waited)) {
        _fail('cleanup_unconfirmed', '原查询进程退出尚未确认。');
      }
      _processReleased = true;
    }
    if (_startAttempted && !_processReleased) {
      _fail('cleanup_unconfirmed', 'START 可能已交付，但缺少原进程的退出证明。');
    }
    // START 前脚本只阻塞读取授权，尚未创建任何查询子进程。
    _released = true;
  }

  String get _identity =>
      '''
p=$_pid
expected=$_started
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

  Future<String> _inspect(String command) async {
    final tag = '__INTEROP_QUERY_CHECK_${_nonce()}__:';
    final session = await connection.client.services.exec(
      connection.device,
      'sh -c ${_quote(command)}; result=\$?; printf ${_quote('\n$tag%s\n')} "\$result"',
      timeout: timeout,
    );
    _checks.add(session);
    try {
      final output = BytesBuilder(copy: false);
      await for (final event in session.events) {
        if (output.length + event.bytes.length > 8192) {
          _fail('output_limit', '查询进程核验输出超过限制。');
        }
        output.add(event.bytes);
      }
      final text = utf8.decode(output.takeBytes());
      final marker = RegExp('\n${RegExp.escape(tag)}([0-9]+)\n\$')
          .firstMatch(text);
      if (marker == null || marker[1] != '0') {
        _fail('cleanup_unconfirmed', '查询进程核验没有返回成功的真实终态。');
      }
      return text.substring(0, marker.start);
    } finally {
      await session.close();
      _checks.remove(session);
    }
  }

  String get _launch =>
      '''
IFS= read -r authorization || exit 40
[ "\$authorization" = ${_quote('START $_token')} ] || exit 40
child=''
watcher=''
terminal=false
cleanup() {
  trap - EXIT
  trap '' HUP INT TERM USR1
  if [ -n "\$child" ] && [ "\$terminal" = false ]; then
    jobs %1 >/dev/null 2>&1
    kill -TERM %1 2>/dev/null
    kill -CONT %1 2>/dev/null
    wait "\$child" 2>/dev/null
    result=\$?
    terminal=true
    printf ${_quote('\n$_endPrefix%s\n')} "\$result"
  fi
  if [ -n "\$watcher" ]; then
    jobs %2 >/dev/null 2>&1
    kill -TERM %2 2>/dev/null
    wait "\$watcher" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP USR1
trap 'exit 130' INT
trap 'exit 143' TERM
sh -c ${_quote('''
IFS= read -r own_stat < /proc/self/stat || exit 40
own_pid=\${own_stat%% *}
kill -STOP "\$own_pid" || exit 40
CLASSPATH=${_quote(jarPath)} exec app_process / --nice-name=${_quote(_nice)} com.genymobile.scrcpy.Server 5.0.1 $option=true cleanup=false log_level=info
''')} ${_quote(_nice)} </dev/null &
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
print -r -- "$_readyPrefix\$child:\$started"
IFS= read -r authorization || exit 40
[ "\$authorization" = ${_quote('RUN $_token')} ] || exit 40
watch_input() {
  while IFS= read -r line; do
    if [ "\$line" = ${_quote('STOP $_token')} ]; then break; fi
  done
  kill -USR1 \$\$
}
exec 3<&0
watch_input <&3 &
watcher=\$!
exec 3<&-
jobs %1 >/dev/null 2>&1
kill -CONT %1 2>/dev/null || exit 40
wait "\$child"
result=\$?
terminal=true
printf ${_quote('\n$_endPrefix%s\n')} "\$result"
exit "\$result"
''';
}
