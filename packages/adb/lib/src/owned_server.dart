part of 'api.dart';

/// 官方 ADB 子进程的启动事实；命令参数、密钥目录与环境由 Dart 调用方决定。
final class AdbServerLaunchSpec {
  AdbServerLaunchSpec({
    required this.executable,
    required Iterable<String> arguments,
    required Map<String, String> environment,
    required this.endpoint,
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment);

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String endpoint;
}

enum AdbServerPhase { reserved, starting, ready, exited }

/// 同一原生库内登记的真实子进程；PID 和端点仅供诊断，不授予关闭权限。
final class AdbServerInfo {
  const AdbServerInfo({
    required this.serverId,
    required this.leaseId,
    required this.launch,
    required this.phase,
    required this.transportStateUnknown,
    this.pid,
    this.exitCode,
  });

  final String serverId;

  /// 当前控制权限；认领后轮换，旧值无法操作或关闭后继。
  final String leaseId;
  final AdbServerLaunchSpec launch;
  final AdbServerPhase phase;

  /// 是否存在已发出却未确认的连接命令。
  ///
  /// 该事实跨认领保留，只允许关闭原进程。
  final bool transportStateUnknown;
  final int? pid;
  final int? exitCode;
}

/// 先登记完整参数再启动，isolate 消失也不会留下未登记的 CLI 子进程。
final class AdbServerCommandSpec {
  AdbServerCommandSpec({
    required this.executable,
    required Iterable<String> arguments,
    required Uint8List input,
    required this.timeoutMs,
    this.mayCreateTransport = false,
    this.preparation = false,
  }) : arguments = List.unmodifiable(arguments),
       input = Uint8List.fromList(input).asUnmodifiableView();

  final String executable;
  final List<String> arguments;
  final Uint8List input;
  final int timeoutMs;
  final bool mayCreateTransport;

  /// 仅限尚未启动服务器时使用，不能绕过运行中服务器的未知状态限制。
  final bool preparation;
}

enum AdbServerCommandStatus {
  exited,
  cancelled,
  timedOut,
  outputLimit,
  startFailed,
  ioFailed,
}

/// 原始输出与真实退出事实；ADB 命令语义和成功回执由 Dart 解释。
final class AdbServerCommandResult {
  AdbServerCommandResult({
    required this.status,
    required this.exitCode,
    required Uint8List stdout,
    required Uint8List stderr,
    this.errorMessage,
  }) : stdout = Uint8List.fromList(stdout).asUnmodifiableView(),
       stderr = Uint8List.fromList(stderr).asUnmodifiableView();

  final AdbServerCommandStatus status;
  final int? exitCode;
  final Uint8List stdout;
  final Uint8List stderr;
  final String? errorMessage;
}

/// 跨 Dart isolate 保留原生 Child、命令与握手的所有权，不暴露 FRB 类型。
abstract interface class NativeAdbServerApi {
  /// 登记不可变的启动输入，暂不创建子进程。
  Future<AdbServerInfo> createServer(AdbServerLaunchSpec launch);

  /// 启动登记的子进程并等待其专用 ACK；协议可用性另行探测。
  Future<AdbServerInfo> startServer(String leaseId, int timeoutMs);

  /// 返回同一原生库中仍保留的登记，包括等待清理的失败资源。
  Future<List<AdbServerInfo>> listServers();

  /// 等待旧 CLI 和未交付握手退出后更换权限；保留已交付的连接和捕获。
  ///
  /// 按旧 lease 比较并交换，并发认领不能撤销刚刚发出的新权限。
  Future<AdbServerInfo> claimServer(String leaseId);

  /// 等待服务器命令、握手和连接释放，再终止原 Child；旧 lease 关闭无害。
  ///
  /// 失败保留登记供重试；捕获的调用方仍须先确认自身捕获已停止。
  Future<void> closeServer(String leaseId);

  /// 固定单次命令的全部输入，暂不创建子进程。
  Future<String> createServerCommand(String leaseId, AdbServerCommandSpec spec);

  /// 启动登记的命令并返回原始输出；连接命令保留待确认标记。
  Future<AdbServerCommandResult> runServerCommand(String commandId);

  /// 仅在 Dart 确认该命令已建立可用传输后调用；不能解除其他命令的未知结果。
  Future<void> confirmServerCommand(String commandId);

  /// 通知取消命令；完成回执不代表子进程已经退出。
  Future<void> cancelServerCommand(String commandId);

  /// 等待命令子进程实际退出；失败保留同一句柄供重试。
  Future<void> closeServerCommand(String commandId);

  /// 返回既有握手接口使用的句柄；原生同时核验 lease 与服务器端点。
  Future<String> createServerHandshake(String leaseId);
}

/// 可选的技术准入域；未确认交付的服务器随原域撤权实际排空。
abstract interface class NativeAdbScopedServerApi {
  /// 核验当前 scope 与登记关闭责任必须在原生同一个锁内完成。
  Future<AdbServerInfo> createScopedServer(
    AdbServerLaunchSpec launch,
    String scopeId,
  );

  /// 认领期间也保留未确认责任，旧 scope 不能撤销后继服务器租约。
  Future<AdbServerInfo> claimScopedServer(String leaseId, String scopeId);

  /// 完整交付后才保留 Child 与连接，供后继 scope 精确认领。
  Future<void> confirmScopedServer(String leaseId, String scopeId);
}
