import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'service_models.dart';
part 'services.dart';

/// One-shot cancellation shared by a command and its underlying transport.
final class AdbCancellation {
  final _done = Completer<void>();
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
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
  });

  /// Process-local handle. It must not be persisted as a device identity.
  final String id;
  final String serial;
  final String state;
  final List<String> features;
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

  /// Official adb requires its discovered _adb-tls-connect service fullname.
  final bool forceTlsWithoutMdns;
  final bool androidUsbFd;
}

final class AdbShellEvent {
  const AdbShellEvent(this.channel, this.bytes, {this.exitCode});
  final AdbShellChannel channel;

  /// Unmodified bytes; decoding and output limits belong to the consumer.
  final Uint8List bytes;

  /// Null when legacy adbd supplies no exit status.
  final int? exitCode;
}

/// Platform-neutral ADB service API. Connections/pairing have bounded deadlines;
/// running shell/file operations also accept explicit cancellation. Shell text
/// is an Android shell program. File paths are UTF-8, without shell expansion.
abstract interface class AdbClient {
  AdbCapabilities get capabilities;
  AdbServices get services;
  Future<List<AdbDevice>> devices();
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
  });
  Future<void> disconnect(AdbDevice device);
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Single subscription. Pausing applies transport backpressure; cancelling
  /// closes this command. Legacy adbd may merge stderr and omit its exit code.
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  });

  /// One regular file. Parent directories must already exist. Partial remote
  /// files can remain after an interrupted push, as with original adb.
  Future<int> push(
    AdbDevice device,
    File source,
    String remotePath, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  });

  /// Never overwrites an existing local file; removes partial failures.
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

/// Typed Rust binding seam. device_runtime supplies its generated FRB adapter;
/// flutter_adb has no dependency on application or projection business APIs.
abstract interface class NativeAdbApi {
  Future<AdbDevice> connectServer(
    String serverAddress,
    String serial,
    int timeoutMs,
  );
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
    int timeoutMs,
  );
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs,
  );
  Future<void> disconnect(String id);
  Future<String> pair(
    String address,
    String password,
    String identityPath,
    int timeoutMs,
  );
  Future<String> shell(String id, String command, int timeoutMs);
  Future<String> transfer(
    String id,
    String remotePath,
    String localPath,
    bool push,
    int maxBytes,
    int permissions,
    int modifiedSeconds,
    int timeoutMs,
  );
  Future<NativeAdbEvent?> next(String operationId);
  Future<void> cancel(String operationId);
  Future<void> close();
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
