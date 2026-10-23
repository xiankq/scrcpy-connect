part of 'api.dart';

final class AdbConnectionFacts {
  const AdbConnectionFacts({
    required this.officialServer,
    required this.closed,
    required this.features,
    this.transportId,
    this.protocolVersion,
    this.maxPayload,
    this.burstMode,
  });
  final bool officialServer, closed;
  final List<String> features;
  // Official smart sockets do not expose transport framing/flow-control facts.
  final int? transportId, protocolVersion, maxPayload;
  final bool? burstMode;
}

/// Linux file type and permission bits, unsigned byte size and signed seconds.
/// Legacy SYNC retains its actual 32-bit metadata limitations.
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

/// A remote Linux path. bytes preserves non-UTF8 names returned by SYNC LIST.
final class AdbPath {
  AdbPath.bytes(List<int> value) : bytes = Uint8List.fromList(value) {
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

// Typed binding controls. Public service methods below construct these records;
// a host adapter maps them directly to generated native DTOs, never JSON.
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
  const AdbSyncRequest(
    this.kind,
    this.path, {
    this.localPath = '',
    this.maxBytes = 1 << 40,
    this.maxEntries = 10000,
    this.permissions = 420,
    this.modifiedSeconds = 0,
    this.compression = AdbCompression.none,
  });
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
