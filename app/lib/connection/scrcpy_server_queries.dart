import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';

import '../application/transport/application_command_exception.dart';
import 'connection_owner.dart';
import 'scrcpy_query_process.dart';

final class _ServerQueryJob {
  _ServerQueryJob(this.connection, this.cancellation, this.remote, this.query);
  final _ServerQuery query;
  final DeviceConnection connection;
  final AdbCancellation cancellation;
  final String remote;
  final settled = Completer<void>();
  AdbServiceSession? upload;
  Future<void>? uploadCompletion;
  void Function()? unsubscribe;
  ScrcpyQueryProcess? process;
  Future<void>? cleaning;
  bool cleaned = false;
}

enum _ServerQuery {
  encoders('encoders', 'list_encoders', '编码器', 512 * 1024),
  installedApps('apps', 'list_apps', '已安装应用', 4 * 1024 * 1024);

  const _ServerQuery(this.pathName, this.option, this.label, this.maxBytes);
  final String pathName, option, label;
  final int maxBytes;
  String get errorCode =>
      this == encoders ? 'encoder_probe' : 'apps_unavailable';
  String get cleanupCode => this == encoders
      ? 'encoder_probe_cleanup_unconfirmed'
      : 'apps_cleanup_unconfirmed';
}

/// 共享固定 scrcpy 清单查询的临时部署、真实执行和未确认清理。
/// 不拥有设备连接、窗口或画质策略；应用在全部调用者停止后关闭此唯一实例。
final class ScrcpyServerQueries {
  ScrcpyServerQueries({
    required Uint8List serverBytes,
    String Function()? newId,
    required this.timeout,
  }) : _server = Uint8List.fromList(serverBytes),
       _newId = newId ?? _uuid {
    adbTimeoutMillis(timeout);
  }
  final Uint8List _server;
  final String Function() _newId;
  final Duration timeout;
  final _deployments = <_ServerQueryJob>{};
  final _jobs = <_ServerQueryJob>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<List<Map<String, dynamic>>> encoders(
    DeviceConnection connection,
    AdbCancellation cancellation,
  ) => _query(_ServerQuery.encoders, connection, cancellation);

  /// 返回已安装应用；运行任务仍由互联服务读取，不能由此清单推断。
  Future<List<Map<String, dynamic>>> installedApps(
    DeviceConnection connection,
    AdbCancellation cancellation,
  ) => _query(_ServerQuery.installedApps, connection, cancellation);

  Future<List<Map<String, dynamic>>> _query(
    _ServerQuery query,
    DeviceConnection connection,
    AdbCancellation cancellation,
  ) {
    if (_closed) _fail('disposed', 'scrcpy 清单查询所有者已关闭。');
    cancellation.check();
    if (_server.isEmpty) {
      _fail(query.errorCode, '没有提供受控 scrcpy 服务端，无法查询${query.label}。');
    }
    final remote = '/data/local/tmp/interop-${query.pathName}-${_newId()}.jar';
    if (_deployments.any((job) => job.remote == remote)) {
      _fail(query.errorCode, '该临时部署身份仍由先前查询持有。');
    }
    final job = _ServerQueryJob(connection, cancellation, remote, query);
    _jobs.add(job);
    _deployments.add(job);
    return _execute(job).whenComplete(() {
      // 同一取消令牌可属于多个查询；只能撤销本次实体，不能删掉后继登记。
      _jobs.remove(job);
      job.settled.complete();
    });
  }

  Future<void> _pushServer(_ServerQueryJob job) async {
    final AdbServiceSession session;
    try {
      session = await job.connection.client.services
          .sync(job.connection.device)
          .openPush(
            AdbPath(job.remote),
            maxBytes: _server.length,
            permissions: 384,
            timeout: timeout,
          );
    } catch (_) {
      // 未交付会话的关闭责任仍在 SDK；本对象没有句柄，不能擅自删除其可能仍在写入的路径。
      _deployments.remove(job);
      rethrow;
    }
    job.upload = session;
    // 创建不可丢弃；先持有迟到会话，再绑定可能已经撤销的令牌。
    job.unsubscribe = job.cancellation.onCancel(() {
      unawaited(session.close().catchError((Object _) {}));
    });
    Object? readFailure;
    try {
      job.cancellation.check();
      final reading =
          () async {
            int? transferred;
            await for (final event in session.events) {
              if (event.done) transferred = event.transferred;
            }
            return transferred;
          }().then<int?>(
            (value) => value,
            onError: (Object error, StackTrace stack) {
              readFailure = error;
              Error.throwWithStackTrace(error, stack);
            },
          );
      // 在写入等待期间也观察读取失败，实际错误仍由 await reading 报告。
      job.uploadCompletion = reading.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      await session.addStream(Stream.value(_server));
      await session.finish();
      final transferred = await reading;
      if (transferred != _server.length) {
        _fail(
          job.query == _ServerQuery.encoders
              ? 'encoder_probe_upload'
              : 'apps_upload',
          '${job.query.label}查询服务端上传未返回完整字节回执。',
        );
      }
    } finally {
      if (readFailure != null) {
        // events 结束前已经尝试精确 close；失败后不能在同次查询中隐式重试并丢掉责任。
        _fail(job.query.cleanupCode, '上传流或关闭未完整确认，保留精确会话供停止时核验：$readFailure');
      }
      await _releaseUpload(job);
    }
  }

  Future<void> _releaseUpload(_ServerQueryJob job) async {
    if (job.upload case final session?) {
      try {
        await session.close();
      } catch (error) {
        _fail(job.query.cleanupCode, '上传会话关闭尚未确认，保留精确句柄供重试：$error');
      }
      await job.uploadCompletion;
      job.unsubscribe?.call();
      job.unsubscribe = null;
      job.upload = null;
      job.uploadCompletion = null;
    }
  }

  void cancelForConnection(DeviceConnection connection) {
    for (final job in _jobs.toList()) {
      if (identical(job.connection, connection)) job.cancellation.cancel();
    }
  }

  void cancel() {
    for (final job in _jobs.toList()) {
      job.cancellation.cancel();
    }
  }

  Future<void> stopForConnection(DeviceConnection connection) async {
    cancelForConnection(connection);
    await Future.wait([
      for (final job in _jobs.toList())
        if (identical(job.connection, connection)) job.settled.future,
    ]);
    await _cleanupFiles(connection);
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    cancel();
    final result = () async {
      await Future.wait(_jobs.map((job) => job.settled.future).toList());
      Object? failure;
      StackTrace? failureStack;
      for (final job in _deployments.toList()) {
        try {
          await _cleanupDeployment(job);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    }();
    return _closing = result.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<List<Map<String, dynamic>>> _execute(_ServerQueryJob job) async {
    await _pushServer(job);
    job.cancellation.check();
    final process = job.process = ScrcpyQueryProcess(
      connection: job.connection,
      jarPath: job.remote,
      option: job.query.option,
      maxBytes: job.query.maxBytes,
      timeout: timeout,
    );
    final ScrcpyQueryResult result;
    try {
      result = await process.run(job.cancellation);
    } finally {
      // 读取失败也必须回到同一精确进程；无法确认时仍保留部署和原句柄供停止重试。
      await _cleanupDeployment(job);
    }
    if (result.exitCode != 0) {
      _fail(
        job.query == _ServerQuery.encoders
            ? 'shell_failed'
            : 'apps_unavailable',
        '系统未确认${job.query.label}查询命令成功。',
      );
    }
    final String output;
    try {
      output = utf8.decode(result.stdout);
    } on FormatException {
      _fail(job.query.errorCode, '设备清单不是有效的 UTF-8。');
    }
    return switch (job.query) {
      _ServerQuery.encoders => _parseEncoders(output),
      _ServerQuery.installedApps => _parseApps(output),
    };
  }

  List<Map<String, dynamic>> _parseEncoders(String output) {
    if (!output.contains('List of video encoders:')) {
      _fail('encoder_probe', '设备未返回可识别的编码器列表。');
    }
    final entries = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(output)) {
      if (!line.contains('--video-codec=')) continue;
      final codec = RegExp(r'--video-codec=([A-Za-z0-9]+)(?:\s|$)')
          .firstMatch(line)?[1];
      final encoder = RegExp(r'--video-encoder=([A-Za-z0-9_.-]+)(?:\s|$)')
          .firstMatch(line)?[1];
      if (codec == null ||
          !ScrcpyVideoCodec.values.any((value) => value.name == codec) ||
          encoder == null ||
          encoder.length > 256) {
        _fail('encoder_probe', '设备返回了无效的编码器条目。');
      }
      if (seen.add('$codec/$encoder')) {
        entries.add({
          'codec': codec,
          'name': encoder,
          'available': true,
          'hardware': line.contains('(hw)')
              ? true
              : line.contains('(sw)')
              ? false
              : null,
        });
      }
      if (entries.length > 1024) _fail('encoder_probe', '设备编码器列表超过限额。');
    }
    return entries;
  }

  Future<void> _cleanupFiles(DeviceConnection connection) async {
    Object? failure;
    StackTrace? failureStack;
    for (final job in _deployments.toList()) {
      if (!identical(job.connection, connection)) continue;
      try {
        await _cleanupDeployment(job);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _cleanupDeployment(_ServerQueryJob job) {
    if (job.cleaned) return Future.value();
    if (job.cleaning case final pending?) return pending;
    return job.cleaning = _cleanupDeploymentResources(job)
        .catchError((Object error, StackTrace stack) {
          job.cleaning = null;
          Error.throwWithStackTrace(error, stack);
        });
  }

  Future<void> _cleanupDeploymentResources(_ServerQueryJob job) async {
    await _releaseUpload(job);
    if (job.process case final process?) {
      try {
        await process.close();
      } catch (error) {
        _fail(job.query.cleanupCode, '${job.query.label}查询的精确进程或流尚未回收：$error');
      }
      job.process = null;
    }
    final result = await _run(
      job.connection,
      'rm -f -- ${_quote(job.remote)}',
      maxBytes: 8192,
    );
    if (result.exitCode == null) _fail('result_unknown', '临时查询文件删除结果未知。');
    if (result.exitCode != 0) _fail('shell_failed', '系统未确认临时查询文件已删除。');
    job.cleaned = true;
    _deployments.remove(job);
  }

  // 只供固定清单查询及其文件收尾使用，不对外暴露任意远程执行框架。
  Future<({Uint8List stdout, Uint8List stderr, int? exitCode})> _run(
    DeviceConnection connection,
    String command, {
    AdbCancellation? cancellation,
    required int maxBytes,
  }) async {
    final stdout = BytesBuilder(copy: false),
        stderr = BytesBuilder(copy: false);
    var count = 0, terminal = false;
    int? exitCode;
    await for (final event in connection.client.shell(
      connection.device,
      command,
      cancellation: cancellation,
      timeout: timeout,
    )) {
      cancellation?.check();
      if (terminal) _fail('invalid_data', '设备查询在终态后继续返回数据。');
      count += event.bytes.length;
      if (count > maxBytes) _fail('byte_limit', '设备查询输出超过本次限额。');
      switch (event.channel) {
        case AdbShellChannel.stdout:
          stdout.add(event.bytes);
        case AdbShellChannel.stderr:
          stderr.add(event.bytes);
        case AdbShellChannel.exit:
          if (event.bytes.isNotEmpty) _fail('invalid_data', '设备退出回执包含无效字节。');
          terminal = true;
          exitCode = event.exitCode;
      }
    }
    cancellation?.check();
    if (!terminal) _fail('result_unknown', '设备查询没有返回完整终态。');
    return (
      stdout: stdout.takeBytes(),
      stderr: stderr.takeBytes(),
      exitCode: exitCode,
    );
  }
}

List<Map<String, dynamic>> _parseApps(String output) {
  if (!output.contains('List of apps:')) {
    _fail('apps_unavailable', '设备没有返回可解析的应用列表。');
  }
  final apps = <Map<String, dynamic>>[];
  ({bool system, String name})? pending;
  final package = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$',
  );
  bool validPackage(String value) =>
      value.length <= 230 && package.hasMatch(value);
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
      final system = trimmed.startsWith('*');
      final rest = trimmed.substring(2);
      final inline = RegExp(r'^(.*)\s(\S+)$').firstMatch(rest);
      if (inline != null &&
          inline[2]!.contains('.') &&
          validPackage(inline[2]!)) {
        apps.add({
          'name': inline[1]!.trim(),
          'packageName': inline[2]!,
          'system': system,
        });
        pending = null;
      } else {
        pending = (system: system, name: rest);
      }
    } else if (pending case final previous?) {
      pending = null;
      if (validPackage(trimmed)) {
        apps.add({
          'name': previous.name,
          'packageName': trimmed,
          'system': previous.system,
        });
      }
    }
  }
  return apps;
}

String _quote(String value) {
  if (value.contains('\x00')) _fail('invalid_argument', 'Shell 参数包含无效字符。');
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Never _fail(String code, String message) =>
    throw ApplicationCommandException(code, message);
