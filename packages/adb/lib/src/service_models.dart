part of 'api.dart';

/// 实际观察到的握手，不代表目标设备已证明身份。
enum AdbHandshakeKind {
  unknown,
  plaintext,
  auth,

  /// 已完成 TLS；不证明设备要求或验证了客户端证书。
  tls,

  /// 官方 server 拥有传输，未向 smart socket 提供握手证据。
  delegatedServer,
}

final class AdbConnectionFacts {
  const AdbConnectionFacts({
    required this.officialServer,
    required this.closed,
    required this.features,
    this.connectionId,
    this.serverAddress,
    this.serverId,
    this.admissionScopeKey,
    this.transportId,
    this.protocolVersion,
    this.maxPayload,
    this.burstMode,
    this.handshake = AdbHandshakeKind.unknown,
    this.configuredIdentity,
    this.inboundActivity,
  });
  final bool officialServer, closed;
  final List<String> features;

  /// 进程内底层连接身份；认领不改变此值，只能比较相等，不可作为设备身份持久化。
  final String? connectionId;

  /// 实际配置的官方代理端点；地址相同不能证明服务器进程或传输仍是原实例。
  final String? serverAddress;

  /// 原生登记中实际拥有的服务器身份；外部服务器为空，不根据端口推断。
  final String? serverId;

  /// 最近一次 scoped 握手或认领确认所属的调用方命名域。
  /// 无 scoped 确认时为空；不根据端点或公钥推断，也不代表设备业务身份。
  final String? admissionScopeKey;
  // 官方 smart socket 不公开传输分帧和流控事实。
  final int? transportId, protocolVersion, maxPayload;
  final bool? burstMode;
  final AdbHandshakeKind handshake;

  /// 连接建立时配置的公钥指纹；不会随磁盘换钥变化，也不表示已使用该密钥认证。
  final AdbIdentityInfo? configuredIdentity;

  /// 本机实际收到协议流量时变化的不透明标记；仅可比较相等，不表示时间或健康结论。
  /// 旧适配器没有此事实时为空，不可用连接仍登记来推断发生过入站活动。
  final String? inboundActivity;
}

/// Linux 文件类型与权限位、无符号字节大小和有符号秒数。
/// 旧 SYNC 仍保留实际的 32 位元数据限制。
final class AdbFileMetadata {
  const AdbFileMetadata(this.mode, this.size, this.modifiedSeconds);
  final int mode, size, modifiedSeconds;
  bool get isDirectory => mode & 0xf000 == 0x4000;
  bool get isFile => mode & 0xf000 == 0x8000;
  bool get isSymlink => mode & 0xf000 == 0xa000;
}

final class AdbDirectoryEntry {
  const AdbDirectoryEntry(this.name, this.metadata);
  final Uint8List name;
  final AdbFileMetadata metadata;
}

final class AdbReverseMapping {
  const AdbReverseMapping(this.serial, this.deviceService, this.hostService);
  final String serial, deviceService, hostService;
}

final class AdbServiceFacts {
  const AdbServiceFacts({
    this.metadata,
    this.entries = const [],
    this.pids = const [],
    this.mappings = const [],
    this.deviceService,
  });
  final AdbFileMetadata? metadata;
  final List<AdbDirectoryEntry> entries;
  final List<int> pids;
  final List<AdbReverseMapping> mappings;
  final String? deviceService;
}

enum AdbServiceKind {
  raw,
  exec,
  shellRaw,
  shellPty,
  abb,
  abbExec,
  cmd,
  response,
  reboot,
  tcpIp,
  usb,
  jdwp,
  trackJdwp,
}

enum AdbSyncKind { stat, lstat, list, pull, push, pullFile, pushFile }

enum AdbCompression { none, brotli, lz4, zstd }

enum AdbInputKind { bytes, closeStdin, resize, finish }

enum AdbRebootTarget { system, recovery, bootloader, fastboot, sideload }

enum AdbReverseKind { forward, list, remove, removeAll }

/// 远程 Linux 路径；bytes 保留 SYNC LIST 返回的非 UTF-8 名称。
final class AdbPath {
  AdbPath.bytes(List<int> value)
    : bytes = Uint8List.fromList(value).asUnmodifiableView() {
    if (bytes.isEmpty || bytes.length > 1024 || bytes.contains(0)) {
      throw ArgumentError('Invalid ADB path');
    }
  }
  factory AdbPath(String value) => AdbPath.bytes(utf8.encode(value));
  final Uint8List bytes;
}

final class AdbSocket {
  AdbSocket._(this.service);
  factory AdbSocket.tcp(int port) {
    if (port <= 0 || port > 65535) throw ArgumentError.value(port, 'port');
    return AdbSocket._('tcp:$port');
  }
  factory AdbSocket.jdwp(int pid) {
    if (pid <= 0) throw ArgumentError.value(pid, 'pid');
    return AdbSocket._('jdwp:$pid');
  }
  factory AdbSocket.vsock(int cid, int port) {
    if (cid < 0 || cid > 0xffffffff || port < 0 || port > 0xffffffff) {
      throw ArgumentError('Invalid vsock address');
    }
    return AdbSocket._('vsock:$cid:$port');
  }
  factory AdbSocket.localAbstract(String name) =>
      AdbSocket._local('localabstract', name);
  factory AdbSocket.localFilesystem(String name) =>
      AdbSocket._local('localfilesystem', name);
  factory AdbSocket.localReserved(String name) =>
      AdbSocket._local('localreserved', name);
  factory AdbSocket._local(String prefix, String name) {
    validateAdbPath(name);
    return AdbSocket._('$prefix:$name');
  }
  final String service;
}

final class AdbReverseSocket {
  AdbReverseSocket._(this.service);
  factory AdbReverseSocket.tcp(int port) {
    if (port < 0 || port > 65535) throw ArgumentError.value(port, 'port');
    return AdbReverseSocket._('tcp:$port');
  }
  factory AdbReverseSocket.localAbstract(String name) =>
      AdbReverseSocket._local('localabstract', name);
  factory AdbReverseSocket.localFilesystem(String name) =>
      AdbReverseSocket._local('localfilesystem', name);
  factory AdbReverseSocket._local(String prefix, String name) {
    validateAdbPath(name);
    if (name.contains(';') || name.contains(':')) {
      throw ArgumentError('Invalid reverse socket');
    }
    return AdbReverseSocket._('$prefix:$name');
  }
  final String service;
}

// 类型化绑定控制；下方公开方法构建这些记录，由宿主 adapter 直接映射为生成的原生 DTO，不经过 JSON。
final class AdbServiceRequest {
  const AdbServiceRequest(
    this.kind, {
    this.service = '',
    this.arguments = const [],
    this.maxOutput = 65536,
  });
  final AdbServiceKind kind;
  final String service;
  final List<String> arguments;
  final int maxOutput;
}

final class AdbSyncRequest {
  AdbSyncRequest(
    this.kind,
    Uint8List path, {
    this.localPath = '',
    this.maxBytes = 1 << 40,
    this.maxEntries = 10000,
    this.permissions = 420,
    this.modifiedSeconds = 0,
    this.compression = AdbCompression.none,
  }) : path = Uint8List.fromList(path).asUnmodifiableView();
  final AdbSyncKind kind;
  final Uint8List path;
  final String localPath;
  final int maxBytes, maxEntries, permissions, modifiedSeconds;
  final AdbCompression compression;
}

final class AdbServiceInput {
  AdbServiceInput(
    this.kind, {
    Uint8List? bytes,
    this.rows = 0,
    this.columns = 0,
  }) : bytes = bytes ?? Uint8List(0);
  final AdbInputKind kind;
  final Uint8List bytes;
  final int rows, columns;
}

final class AdbReverseRequest {
  const AdbReverseRequest(
    this.kind, {
    this.deviceService = '',
    this.hostAddress = '',
    this.noRebind = true,
  });
  final AdbReverseKind kind;
  final String deviceService, hostAddress;
  final bool noRebind;
}
