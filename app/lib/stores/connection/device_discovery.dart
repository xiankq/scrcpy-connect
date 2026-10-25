import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';

enum AdbDiscoveryKind { pairing, tlsConnect, tcpConnect }

/// 仅表示当前广播候选，不代表设备身份、配对信任或存活连接。
final class AdbDiscoveryEndpoint {
  const AdbDiscoveryEndpoint({
    required this.kind,
    required this.serviceName,
    required this.instance,
    required this.hostname,
    required this.address,
    required this.port,
    required this.validUntil,
    required this.generation,
  });

  final AdbDiscoveryKind kind;
  final String serviceName, instance, hostname, address;
  final int port, generation;
  final DateTime validUntil;

  String get _key => '$kind\n$serviceName\n$hostname\n$address\n$port';
}

/// 有界发现、候选有效期和 socket 的唯一所有者；不写设备记录或授予信任。
/// 每轮使用新客户端，避免库的缓存命中阻止刷新发送实际查询。
final class DeviceDiscovery {
  DeviceDiscovery({
    this.timeout = const Duration(seconds: 3),
    this.maxServices = 128,
    this.maxEndpoints = 256,
    this.maxConcurrentResolutions = 8,
    MDnsClient Function(RawDatagramSocketFactory)? clientFactory,
    RawDatagramSocketFactory? socketFactory,
    DateTime Function()? now,
    List<InternetAddress>? listenAddresses,
  }) : _clientFactory = clientFactory ?? _defaultClient,
       _socketFactory = socketFactory ?? RawDatagramSocket.bind,
       _now = now ?? DateTime.now,
       _listenAddresses = List.unmodifiable(
         listenAddresses ?? [InternetAddress.anyIPv4, InternetAddress.anyIPv6],
       ) {
    if (timeout <= Duration.zero ||
        timeout > const Duration(minutes: 1) ||
        maxServices < 1 ||
        maxServices > 1024 ||
        maxEndpoints < 1 ||
        maxEndpoints > 4096 ||
        maxConcurrentResolutions < 1 ||
        maxConcurrentResolutions > 32 ||
        _listenAddresses.isEmpty ||
        _listenAddresses.any(
          (address) =>
              address != InternetAddress.anyIPv4 &&
              address != InternetAddress.anyIPv6,
        )) {
      throw ArgumentError('发现期限、容量和监听地址必须有效且有界。');
    }
  }

  final Duration timeout;
  final int maxServices, maxEndpoints, maxConcurrentResolutions;
  final MDnsClient Function(RawDatagramSocketFactory) _clientFactory;
  final RawDatagramSocketFactory _socketFactory;
  final DateTime Function() _now;
  final List<InternetAddress> _listenAddresses;
  final _operations = <_DiscoveryScan>{};
  final _endpoints = <String, AdbDiscoveryEndpoint>{};
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  _DiscoveryScan? _latest;
  bool _closed = false;
  int _generation = 0;

  static MDnsClient _defaultClient(RawDatagramSocketFactory sockets) =>
      MDnsClient(rawDatagramSocketFactory: sockets);

  /// 只允许 GUID 本身或 mDNS 的数字冲突别名；名称前缀不构成身份。
  static bool matchesGuid(String instance, String guid) =>
      guid.isNotEmpty &&
      (instance == guid ||
          RegExp('^${RegExp.escape(guid)} \\([0-9]+\\)\$').hasMatch(instance));

  /// 新轮同步撤销旧轮准入，等待它实际停止后再创建新 socket。
  /// 取消或失败不发布残缺扫描；仍有效的旧候选可继续被精确核验。
  Future<List<AdbDiscoveryEndpoint>> scan({
    AdbCancellation? cancellation,
    String? pairingInstance,
  }) {
    if (_closed) {
      return Future.error(
        const ApplicationCommandException('disposed', '发现所有者已关闭。'),
      );
    }
    if (pairingInstance != null &&
        (pairingInstance.isEmpty ||
            pairingInstance.length > 255 ||
            pairingInstance.contains(RegExp(r'[\r\n\x00]')))) {
      return Future.error(
        const ApplicationCommandException('invalid_argument', '配对服务名无效。'),
      );
    }
    for (final old in _operations) {
      old.stop(const ApplicationCommandException('cancelled', '已被后继发现请求取代。'));
    }
    final operation = _DiscoveryScan();
    _latest = operation;
    _operations.add(operation);
    final unregister = cancellation?.onCancel(
      () => operation.stop(
        const ApplicationCommandException('cancelled', '本次发现已取消。'),
      ),
    );
    final result = _tail.then((_) => _run(operation, pairingInstance));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result.whenComplete(() => unregister?.call());
  }

  bool isCurrent(AdbDiscoveryEndpoint endpoint) {
    if (_closed) return false;
    _expire();
    return _endpoints[endpoint._key]?.generation == endpoint.generation;
  }

  void _expire() =>
      _endpoints.removeWhere((_, item) => !item.validUntil.isAfter(_now()));

  Future<List<AdbDiscoveryEndpoint>> _run(
    _DiscoveryScan operation,
    String? pairingInstance,
  ) async {
    Timer? deadline;
    var cleanupAttempted = false;
    try {
      operation.check();
      for (final old in _operations.toList()) {
        if (!identical(old, operation) && old.finished) await _cleanup(old);
      }
      operation.check();
      deadline = Timer(timeout, operation.endWindow);
      final clients = <MDnsClient>[];
      final startupErrors = <Object>[];
      await Future.wait([
        for (final address in _listenAddresses)
          () async {
            final client = _clientFactory((
              host,
              port, {
              bool reuseAddress = true,
              bool reusePort = true,
              int ttl = 1,
            }) async {
              final socket = await _socketFactory(
                host,
                port,
                reuseAddress: reuseAddress,
                reusePort: reusePort,
                ttl: ttl,
              );
              // 即使 start 尚未交付或随后抛错，也必须拥有已经创建的 socket。
              operation.sockets.add(socket);
              return socket;
            });
            operation.clients.add(client);
            try {
              await client.start(
                listenAddress: address,
                onError: (Object error) => operation.stop(error),
              );
              clients.add(client);
            } catch (error) {
              startupErrors.add(error);
            }
          }(),
      ]);
      operation.check();
      if (clients.isEmpty) {
        throw ApplicationCommandException(
          'discovery_unavailable',
          '无法打开多播发现：${startupErrors.firstOrNull}',
        );
      }
      if (operation.windowEnded) {
        throw const ApplicationCommandException('timeout', '多播发现启动超时。');
      }
      final queue = Queue<Future<void> Function()>();
      final running = <Future<void>>{};
      final services = <String>{};
      final queried = <(MDnsClient, String)>{};
      final found = <String, AdbDiscoveryEndpoint>{};
      final removed = <String>{};
      final removedEndpoints = <String>{};

      void pump() {
        while (!operation.stopped &&
            !operation.windowEnded &&
            queue.isNotEmpty &&
            running.length < maxConcurrentResolutions) {
          late Future<void> work;
          work = queue
              .removeFirst()()
              .catchError((Object error, StackTrace stack) {
                operation.stop(error);
              })
              .whenComplete(() {
                running.remove(work);
                pump();
              });
          running.add(work);
        }
      }

      void pointer(
        MDnsClient client,
        AdbDiscoveryKind kind,
        String suffix,
        PtrResourceRecord record,
      ) {
        final fullname = _canonical(record.domainName);
        if (!fullname.toLowerCase().endsWith('.$suffix')) return;
        final instance = fullname.substring(
          0,
          fullname.length - suffix.length - 1,
        );
        if (fullname.length > 255 ||
            instance.isEmpty ||
            fullname.contains(RegExp(r'[\r\n\x00]'))) {
          return;
        }
        if (pairingInstance != null && instance != pairingInstance) return;
        if (record.validUntil <= _now().millisecondsSinceEpoch) {
          removed.add(fullname);
          return;
        }
        if (!services.contains(fullname) && services.length >= maxServices) {
          throw const ApplicationCommandException(
            'discovery_limit',
            '发现服务超过本次查询上限。',
          );
        }
        services.add(fullname);
        if (!queried.add((client, fullname))) return;
        queue.add(
          () => _resolve(
            operation,
            client,
            kind,
            fullname,
            instance,
            record.validUntil,
            found,
            removed,
            removedEndpoints,
          ),
        );
        pump();
      }

      await Future.wait([
        for (final client in clients)
          for (final (kind, suffix) in _services)
            if (pairingInstance == null || kind == AdbDiscoveryKind.pairing)
              _query<PtrResourceRecord>(
                operation,
                client,
                ResourceRecordQuery.serverPointer(suffix),
                (record) => pointer(client, kind, suffix, record),
              ),
      ]);
      while (running.isNotEmpty) {
        await Future.wait(running.toList());
      }
      operation.check();
      cleanupAttempted = true;
      await _cleanup(operation);
      operation.check();
      if (_closed || !identical(_latest, operation)) {
        throw const ApplicationCommandException('cancelled', '本次发现已结束或被后继取代。');
      }
      _expire();
      // 一轮完整服务解析替换该服务的旧地址；无回答只能由 TTL 失效，不能假定离线。
      final resolved = found.values.map((item) => item.serviceName).toSet();
      final retained = Map.of(_endpoints)
        ..removeWhere(
          (key, item) =>
              removed.contains(item.serviceName) ||
              removedEndpoints.contains(key) ||
              resolved.contains(item.serviceName) && !found.containsKey(key),
        );
      for (final entry in found.entries) {
        final item = entry.value;
        if (removed.contains(item.serviceName) ||
            !item.validUntil.isAfter(_now())) {
          continue;
        }
        final previous = retained[entry.key];
        retained[entry.key] = AdbDiscoveryEndpoint(
          kind: item.kind,
          serviceName: item.serviceName,
          instance: item.instance,
          hostname: item.hostname,
          address: item.address,
          port: item.port,
          validUntil: item.validUntil,
          generation: previous?.generation ?? ++_generation,
        );
      }
      if (retained.length > maxEndpoints) {
        throw const ApplicationCommandException(
          'discovery_limit',
          '有效发现缓存超过端点上限。',
        );
      }
      _endpoints
        ..clear()
        ..addAll(retained);
      return List.unmodifiable(
        _endpoints.values
            .where(
              (item) =>
                  pairingInstance == null ||
                  item.kind == AdbDiscoveryKind.pairing &&
                      item.instance == pairingInstance,
            )
            .toList()
          ..sort((a, b) => a._key.compareTo(b._key)),
      );
    } finally {
      deadline?.cancel();
      operation.finished = true;
      if (!cleanupAttempted) await _cleanup(operation);
    }
  }

  Future<void> _resolve(
    _DiscoveryScan operation,
    MDnsClient client,
    AdbDiscoveryKind kind,
    String fullname,
    String instance,
    int ptrExpiry,
    Map<String, AdbDiscoveryEndpoint> found,
    Set<String> removed,
    Set<String> removedEndpoints,
  ) async {
    final addresses = <Future<void>>[];
    final targets = <String>{};
    await _query<SrvResourceRecord>(
      operation,
      client,
      ResourceRecordQuery.service(fullname),
      (srv) {
        if (srv.validUntil <= _now().millisecondsSinceEpoch) {
          removed.add(fullname);
          return;
        }
        if (srv.port < 1 ||
            srv.port > 65535 ||
            srv.target.length > 255 ||
            srv.target.isEmpty) {
          return;
        }
        final hostname = _canonical(srv.target);
        if (!targets.add('$hostname:${srv.port}')) return;
        if (targets.length > 8) {
          throw const ApplicationCommandException(
            'discovery_limit',
            '服务目标数量超过上限。',
          );
        }
        for (final query in [
          ResourceRecordQuery.addressIPv4(hostname),
          ResourceRecordQuery.addressIPv6(hostname),
        ]) {
          addresses.add(
            _query<IPAddressResourceRecord>(operation, client, query, (record) {
              final ip = record.address;
              // DNS AAAA 不携带接口索引；未带 zone 的链路本地地址不能交给连接层猜测接口。
              if (ip.isMulticast ||
                  ip.isLoopback ||
                  ip.isLinkLocal && !ip.address.contains('%') ||
                  ip.rawAddress.every((byte) => byte == 0)) {
                return;
              }
              final expiry = [
                ptrExpiry,
                srv.validUntil,
                record.validUntil,
              ].reduce((a, b) => a < b ? a : b);
              final endpoint = AdbDiscoveryEndpoint(
                kind: kind,
                serviceName: fullname,
                instance: instance,
                hostname: hostname,
                address: ip.address,
                port: srv.port,
                validUntil: DateTime.fromMillisecondsSinceEpoch(
                  expiry,
                  isUtc: true,
                ),
                generation: 0,
              );
              if (expiry <= _now().millisecondsSinceEpoch) {
                removedEndpoints.add(endpoint._key);
                found.remove(endpoint._key);
                return;
              }
              if (!found.containsKey(endpoint._key) &&
                  found.length >= maxEndpoints) {
                throw const ApplicationCommandException(
                  'discovery_limit',
                  '发现端点超过本次查询上限。',
                );
              }
              found[endpoint._key] = endpoint;
            }).catchError((Object error, StackTrace stack) {
              operation.stop(error);
            }),
          );
        }
      },
    );
    await Future.wait(addresses);
  }

  Future<void> _query<T extends ResourceRecord>(
    _DiscoveryScan operation,
    MDnsClient client,
    ResourceRecordQuery query,
    void Function(T) accept,
  ) async {
    operation.check();
    if (operation.windowEnded) return;
    final done = Completer<void>();
    var count = 0;
    final subscription = client
        .lookup<T>(query, timeout: timeout)
        .listen(
          (record) {
            if (done.isCompleted ||
                operation.stopped ||
                operation.windowEnded) {
              return;
            }
            try {
              if (++count > 1024) {
                throw const ApplicationCommandException(
                  'discovery_limit',
                  '发现响应超过本次查询上限。',
                );
              }
              accept(record);
            } catch (error, stack) {
              done.completeError(error, stack);
              operation.stop(error);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    operation.subscriptions.add(subscription);
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    operation.pending.add(finish);
    try {
      await done.future;
      operation.check();
    } finally {
      operation.pending.remove(finish);
      await subscription.cancel();
      operation.subscriptions.remove(subscription);
    }
  }

  Future<void> _cleanup(_DiscoveryScan operation) async {
    operation.endWindow();
    Object? failure;
    for (final client in operation.clients.toList()) {
      try {
        client.stop();
        operation.clients.remove(client);
      } catch (error) {
        failure ??= error;
      }
    }
    for (final subscription in operation.subscriptions.toList()) {
      try {
        await subscription.cancel();
        operation.subscriptions.remove(subscription);
      } catch (error) {
        failure ??= error;
      }
    }
    for (final socket in operation.sockets.toList()) {
      try {
        socket.close();
        operation.sockets.remove(socket);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) {
      throw ApplicationCommandException(
        'discovery_cleanup_unconfirmed',
        '发现资源尚未确认释放：$failure',
      );
    }
    _operations.remove(operation);
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    _latest = null;
    for (final operation in _operations) {
      operation.stop(
        const ApplicationCommandException('cancelled', '发现所有者已关闭。'),
      );
    }
    final closing = () async {
      await _tail;
      for (final operation in _operations.toList()) {
        await _cleanup(operation);
      }
      _endpoints.clear();
    }();
    return _closing = closing.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }
}

final class _DiscoveryScan {
  final sockets = <RawDatagramSocket>{};
  final clients = <MDnsClient>{};
  final pending = <void Function()>{};
  final subscriptions = <StreamSubscription<ResourceRecord>>{};
  bool windowEnded = false, finished = false;
  Object? failure;
  bool get stopped => failure != null;
  void check() {
    if (failure case final error?) throw error;
  }

  void stop(Object error) {
    failure ??= error;
    endWindow();
  }

  void endWindow() {
    windowEnded = true;
    for (final finish in pending.toList()) {
      finish();
    }
  }
}

String _canonical(String name) =>
    name.endsWith('.') ? name.substring(0, name.length - 1) : name;

const _services = [
  (AdbDiscoveryKind.pairing, '_adb-tls-pairing._tcp.local'),
  (AdbDiscoveryKind.tlsConnect, '_adb-tls-connect._tcp.local'),
  (AdbDiscoveryKind.tcpConnect, '_adb._tcp.local'),
];
