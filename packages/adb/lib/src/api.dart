import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'connection_options.dart';
export 'connection_options.dart';

part 'service_models.dart';
part 'services.dart';
part 'open_probe.dart';
part 'files.dart';
part 'identities.dart';
part 'owned_server.dart';

/// 命令与底层传输共享的一次性取消。
final class AdbCancellation {
  final _done = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (_done.isCompleted) return;
    _done.complete();
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    Object? failure;
    StackTrace? failureStack;
    for (final listener in listeners) {
      try {
        listener();
      } catch (error, stack) {
        // 一个观察者失败不能阻止其他传输收到同一次撤销。
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  /// 注册可移除的取消监听；操作结束时解绑，长期 token 不保留历史 worker。
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  void check() {
    if (isCancelled) throw const AdbException('cancelled');
  }
}

final class AdbException implements Exception {
  const AdbException(this.code, [this.message = '']);
  final String code;
  final String message;
  @override
  String toString() =>
      'AdbException($code${message.isEmpty ? '' : ': $message'})';
}

final class AdbDevice {
  const AdbDevice({
    required this.id,
    required this.serial,
    required this.state,
    this.features = const [],
    this.nativeOwner,
  });

  /// 当前操作与关闭权限的进程内句柄；认领后更换，不可作为设备或物理连接身份持久化。
  final String id;
  final String serial;
  final String state;
  final List<String> features;

  /// 原生宿主的进程内身份；仅用于阻止不同动态库之间误用句柄，不可序列化。
  final Object? nativeOwner;
}

/// 官方服务器当前列出的传输事实；不是已认领的连接或设备记录。
/// 只有明确返回 [usbPath] 才有 USB 路径事实，不从序列号或名称推断传输类型。
final class AdbTransport {
  const AdbTransport({
    required this.serial,
    required this.state,
    this.usbPath,
    this.model,
    this.product,
    this.device,
    this.transportId,
  });
  final String serial, state;
  final String? usbPath, model, product, device;

  /// 服务器本次返回的 transport_id；不可跨服务器或重启持久化为设备身份。
  final int? transportId;
}

/// 列举服务器可见传输，不建立连接，不过滤未授权或离线设备。
abstract interface class AdbTransportDiscovery {
  /// 取消等待本次受控 CLI 实际退出；不关闭服务器或其它连接。
  Future<List<AdbTransport>> transports({
    Duration timeout = const Duration(seconds: 3),
    AdbCancellation? cancellation,
  });
}

enum AdbShellChannel { stdout, stderr, exit }

final class AdbCapabilities {
  const AdbCapabilities({
    required this.officialServer,
    required this.suppressAuthorizationPrompt,
    required this.forceTlsWithoutMdns,
    required this.androidUsbFd,
  });
  final bool officialServer;
  final bool suppressAuthorizationPrompt;

  /// 官方 adb 要求已发现的 _adb-tls-connect 完整服务名称。
  final bool forceTlsWithoutMdns;
  final bool androidUsbFd;
}

final class AdbShellEvent {
  const AdbShellEvent(this.channel, this.bytes, {this.exitCode});
  final AdbShellChannel channel;

  /// 未经修改的字节；解码和输出限额由消费者负责。
  final Uint8List bytes;

  /// 旧 adbd 不提供退出状态时为 null。
  final int? exitCode;
}

/// 跨平台 ADB 能力接口；连接、配对、shell 和文件操作支持显式取消。
/// shell 文本是 Android shell 程序，文件路径使用 UTF-8 且不进行 shell 展开。
abstract interface class AdbClient {
  AdbCapabilities get capabilities;
  AdbServices get services;
  Future<List<AdbDevice>> devices();

  /// [directOptions] 仅适用于直连传输；官方服务器拒绝显式传入此参数，不能冒充已应用。
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions? directOptions,
    AdbCancellation? cancellation,
  });
  Future<void> disconnect(AdbDevice device);

  /// 取消等待实际握手结束；对端可能已保存信任，取消不表示撤销配对。
  /// 已取得的真实成功结果仍然返回，调用方不能据取消意图推断授权未发生。
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
    AdbCancellation? cancellation,
  });

  /// 单订阅；暂停施加传输背压，取消关闭本命令。
  /// 旧 adbd 可能合并 stderr 且不提供退出码。
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  });

  /// 单个普通文件，父目录必须已存在；与原始 adb 一样，中断 push 后可能保留部分远端文件。
  Future<int> push(
    AdbDevice device,
    File source,
    String remotePath, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  });

  /// 不覆盖已有本机文件，失败时删除部分产物。
  Future<int> pull(
    AdbDevice device,
    String remotePath,
    File destination, {
    int maxBytes = 1 << 40,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  });
  Future<void> close();
}

/// 认领同一原生宿主内的现存连接，撤销旧操作权限而保留底层传输和既有捕获。
abstract interface class AdbConnectionClaims {
  /// 等待旧服务操作退出后返回新句柄；旧句柄不能再操作或关闭该连接。
  /// 调用方须先确认目标归属；此操作不验证设备身份或官方服务器进程身份。
  Future<AdbDevice> claimConnection(AdbDevice device);
}

/// 类型化原生传输接口，由宿主注入绑定适配器；本包不依赖应用或投影业务。
abstract interface class NativeAdbApi {
  Future<AdbDevice> connectServer(
    String serverAddress,
    String serial,
    int timeoutMs, {
    String? handshakeId,
  });
  Future<AdbConnectionFacts> connectionFacts(String id);
  Future<String> service(String id, AdbServiceRequest request, int timeoutMs);
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs);
  Future<void> write(String id, AdbServiceInput input);
  Future<String> reverse(String id, AdbReverseRequest request, int timeoutMs);
  Future<List<AdbDevice>> devices();
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  });
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  });
  Future<void> disconnect(String id);
  Future<String> pair(
    String address,
    String password,
    String identityPath,
    int timeoutMs, {
    String? handshakeId,
  });
  Future<String> shell(String id, String command, int timeoutMs);
  Future<NativeAdbEvent?> next(String operationId);
  Future<void> cancel(String operationId);
  Future<void> close();
}

/// 原生握手的单次准入与取消；句柄由能力适配器隐藏，不作为设备身份。
abstract interface class NativeAdbHandshakeApi {
  Future<String> createHandshake();

  /// 仅通知实际握手取消；资源释放由 [closeHandshake] 确认。
  Future<void> cancelHandshake(String handshakeId);

  /// 撤销未开始的准入，或等待在途握手退出；失败保留同句柄重试权。
  Future<void> closeHandshake(String handshakeId);
}

/// 调用方提供的技术准入域事实；策略、设备记录和密钥路径仍由调用方保存。
final class AdbAdmissionScopeInfo {
  const AdbAdmissionScopeInfo({
    required this.scopeKey,
    required this.scopeId,
    required this.accepting,
  });
  final String scopeKey, scopeId;
  final bool accepting;
}

/// 跨 isolate 接管握手；成功交付的 Client 独立存活，未确认结果必须实际回收。
abstract interface class NativeAdbAdmissionApi {
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String scopeKey);

  /// expectedScopeId 为空仅创建不存在的域，非空时按旧权限比较并交换。
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String scopeKey, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  });

  /// 旧权限关闭无害；失败保留同一域和实际资源，可使用原 ID 重试。
  Future<void> closeAdmissionScope(String scopeId, {int timeoutMs = 7000});
  Future<String> createScopedHandshake(String scopeId);

  /// 客户端登记精确关闭权后调用，确认之前不能开始连接服务或捕获。
  Future<void> confirmHandshakeConnection(
    String handshakeId,
    String connectionId,
  );
  Future<AdbDevice> claimScopedConnection(
    String connectionId,
    String handshakeId,
  );
}

/// 原生连接的独占权限交接；适配器隐藏注册表和句柄更换。
abstract interface class NativeAdbConnectionApi {
  Future<AdbDevice> claimConnection(String connectionId);
}

final class NativeAdbEvent {
  const NativeAdbEvent({
    required this.kind,
    required this.bytes,
    required this.done,
    this.exitCode,
    this.transferred = 0,
    this.facts,
  });
  final String kind;
  final Uint8List bytes;
  final bool done;
  final int? exitCode;
  final int transferred;
  final AdbServiceFacts? facts;
}

int adbTimeoutMillis(Duration timeout) {
  final value = timeout.inMilliseconds;
  if (value <= 0 || value > 86400000) {
    throw ArgumentError.value(
      timeout,
      'timeout',
      'must be greater than zero and at most one day',
    );
  }
  return value;
}

void validateAdbPath(String path) {
  if (path.isEmpty || path.contains('\u0000')) {
    throw ArgumentError.value(path, 'path');
  }
}
