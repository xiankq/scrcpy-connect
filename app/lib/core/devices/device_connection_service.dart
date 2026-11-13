import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/adb_discovery_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/devices/usb_authorization.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

/// 产品设置流程的唯一所有者；直接调用 Dart 能力并等待真实执行结束。
/// 配对信任、监听切换与连接交付是三个独立事实，取消不能抹去已发生的前两项。
class DeviceConnectionService implements DeviceSetup {
  DeviceConnectionService({
    required this.devices,
    required this.discovery,
    required this.clientForIdentity,
    required this.releaseIdentityClient,
    required this.policy,
    required this.isStateUnverified,
    this.authorizeUsb,
    this.cancelUsb,
    this.holdDevice,
    bool Function()? burstMode,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    Random? random,
  }) : _burstMode = burstMode ?? (() => false),
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final DeviceService devices;
  final DeviceDiscovery discovery;
  final FutureOr<AdbClient> Function(IdentitySelection) clientForIdentity;
  final Future<void> Function(IdentitySelection) releaseIdentityClient;
  final ConnectionPolicy policy;
  final bool Function() isStateUnverified;
  final Future<UsbAccess> Function(UsbAuthorizationRequest)? authorizeUsb;
  final Future<void> Function(String attemptId)? cancelUsb;
  final Future<void> Function() Function(String)? holdDevice;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  final Random _random;
  final bool Function() _burstMode;
  final _flows = <_SetupFlow>{};
  final _stops = <String, int>{};
  bool _disposed = false;
  int _next = 0, _revision = 0;

  /// 先同步撤准入，再等待真实任务；身份变更或删除记录不能越过迟到配对回执。
  Future<void> prepareChange(ConnectionChange change) async {
    final id = change.deviceId;
    if (id != null &&
        (change.kind == ConnectionChangeKind.connect ||
            change.kind == ConnectionChangeKind.configure ||
            change.kind == ConnectionChangeKind.stop)) {
      _stops[id] = ++_revision;
    }
    final affected = _flows
        .where(
          (flow) => switch (change.kind) {
            ConnectionChangeKind.replaceRecords => true,
            ConnectionChangeKind.defaultIdentity => !flow.dedicatedIdentity,
            ConnectionChangeKind.deviceIdentity => flow.deviceId == id,
            // 新配对流程在启动时接管同 attempt/device；直接连接和配置先撤销旧流程。
            _ =>
              change.supersedesSetup &&
                  (change.attemptId == flow.attempt ||
                      id != null && id == flow.deviceId),
          },
        )
        .toList();
    for (final flow in affected) {
      _cancel(flow);
    }
    await Future.wait(affected.map(_drain));
  }

  @override
  Future<List<DiscoveredDevice>> discoverDevices({
    String? attemptId,
    AdbCancellation? cancellation,
  }) async => _start(
    attemptId: attemptId,
    cancellation: cancellation,
    action: _discover,
  ).result;

  @override
  Future<PairingReceipt> pairDevice(
    String address,
    int port,
    String code, {
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) async => _start(
    deviceId: deviceId,
    attemptId: attemptId,
    identity: identity,
    action: (flow) => _pair(flow, address, port, code, identity),
  ).result;

  @override
  Future<QrPairingSession> beginQrPairing({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) async {
    final instance = 'studio-${_secret(12)}';
    final password = _secret(32);
    final started = _start(
      deviceId: deviceId,
      attemptId: attemptId,
      identity: identity,
      timeout: policy.qrPairingTimeout,
      action: (flow) => _qr(flow, identity, instance, password),
    );
    return QrPairingSession(
      attemptId: started.flow.attempt,
      payload: 'WIFI:T:ADB;S:$instance;P:$password;;',
      expiresAt: started.flow.deadline,
      result: started.result,
    );
  }

  @override
  Future<UsbSetupResult> connectUsb({
    String? deviceId,
    String? attemptId,
    String? serial,
    String? usbDeviceId,
    bool connect = false,
    SetupIdentity? identity,
  }) async => _start(
    deviceId: deviceId,
    attemptId: attemptId,
    identity: identity,
    usbRequested: true,
    action: (flow) => _usb(flow, identity, serial, usbDeviceId, connect),
  ).result;

  @override
  Future<WirelessReceipt> enableWireless(
    String deviceId,
    String address, {
    int port = 5555,
    required String connectionId,
    String? attemptId,
  }) async => _start(
    deviceId: deviceId,
    attemptId: attemptId,
    action: (flow) => _tcpip(flow, address, port, connectionId: connectionId),
  ).result;

  ({_SetupFlow flow, Future<T> result}) _start<T>({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
    Duration? timeout,
    bool usbRequested = false,
    AdbCancellation? cancellation,
    required Future<T> Function(_SetupFlow) action,
  }) {
    if (_disposed) {
      throw const RequestFailure('disposed', '连接协调器已释放。');
    }
    policy.validate();
    if (attemptId != null &&
        (attemptId.isEmpty ||
            attemptId.length > 256 ||
            attemptId.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const RequestFailure('invalid_argument', '连接尝试标识无效。');
    }
    if (deviceId != null && !validDeviceId(deviceId)) {
      throw const RequestFailure('invalid_device_id', '设备记录标识无效。');
    }
    if (cancellation?.isCancelled == true) {
      throw const RequestFailure('cancelled', '本次连接流程已停止。');
    }
    final attempt =
        attemptId ?? 'setup-${_now().microsecondsSinceEpoch}-${_next++}';
    final flow = _SetupFlow(
      attempt,
      deviceId,
      _revision,
      _now().add(timeout ?? policy.setupLeaseTimeout),
      identity is DedicatedSetupIdentity,
    );
    final replaced = _flows
        .where(
          (old) =>
              old.attempt == attempt ||
              deviceId != null && old.deviceId == deviceId,
        )
        .toList();
    for (final old in replaced) {
      _cancel(old);
    }
    _flows.add(flow);
    flow.usbRequested = usbRequested;
    final detach = cancellation?.onCancel(flow.stop.cancel);
    flow.timer = Timer(
      flow.deadline.difference(_now()),
      () => _cancel(flow, expired: true),
    );
    final operation = Future.sync(() async {
      try {
        await Future.wait(replaced.map(_drain));
        _bind(flow, flow.deviceId);
        _check(flow);
        final result = await action(flow);
        if (result is DeviceSetupReceipt) flow.receipt = result;
        return result;
      } on AdbException catch (error, stack) {
        Error.throwWithStackTrace(
          DeviceSetupFailure(error.code, error.message, receipt: flow.receipt),
          stack,
        );
      } on RequestFailure catch (error, stack) {
        if (flow.receipt == null) rethrow;
        Error.throwWithStackTrace(
          DeviceSetupFailure(
            error.code,
            error.message,
            receipt: flow.receipt,
            cause: error.details,
          ),
          stack,
        );
      } on DeviceRecordsFailure catch (error, stack) {
        Error.throwWithStackTrace(
          DeviceSetupFailure(
            error.code,
            error.message,
            receipt: flow.receipt,
            cause: error.details,
          ),
          stack,
        );
      } finally {
        detach?.call();
        flow.timer?.cancel();
        flow.settled = true;
        try {
          await _cleanup(flow);
        } catch (error, stack) {
          Error.throwWithStackTrace(
            DeviceSetupFailure(
              'setup_cleanup_unconfirmed',
              '连接流程的资源尚未确认释放：$error',
              receipt: flow.receipt,
              cause: error,
            ),
            stack,
          );
        }
      }
    });
    flow.work = operation;
    // 完成可早于调用方取得 QR 句柄；登记观察者不改变其后来等待到的结果。
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return (flow: flow, result: operation);
  }

  String _secret(int bytes) =>
      base64UrlEncode(List.generate(bytes, (_) => _random.nextInt(256)))
          .replaceAll('=', '');

  Future<List<DiscoveredDevice>> _discover(_SetupFlow flow) async {
    final endpoints = await discovery.scan(cancellation: flow.stop);
    _check(flow);
    final grouped = <String, List<AdbDiscoveryEndpoint>>{};
    for (final endpoint in endpoints) {
      grouped.putIfAbsent(endpoint.serviceName, () => []).add(endpoint);
    }
    return List.unmodifiable([
      for (final group in grouped.values) _discoveredService(group),
    ]);
  }

  DiscoveredDevice _discoveredService(List<AdbDiscoveryEndpoint> endpoints) {
    final first = endpoints.first;
    final matches = first.kind == AdbDiscoveryKind.tlsConnect
        ? devices.records.current.devices
              .where(
                (record) =>
                    record.guid != null &&
                    DeviceDiscovery.matchesGuid(first.instance, record.guid!),
              )
              .toList()
        : <DeviceRecord>[];
    return DiscoveredDevice(
      kind: switch (first.kind) {
        AdbDiscoveryKind.pairing => .pairing,
        AdbDiscoveryKind.tlsConnect => .tls,
        AdbDiscoveryKind.tcpConnect => .tcp,
      },
      instance: first.instance,
      serviceName: first.serviceName,
      hostname: first.hostname,
      endpoints: [
        for (final endpoint in endpoints)
          (address: endpoint.address, port: endpoint.port),
      ],
      deviceId: matches.length == 1 ? matches.single.id : null,
    );
  }

  Future<IdentityAttempt> _identity(
    _SetupFlow flow, [
    SetupIdentity? source,
  ]) async {
    final identity = await devices.identities.prepareSetup(
      identity: source,
      deviceId: flow.deviceId,
    );
    flow.identity = identity;
    flow.dedicatedIdentity = identity.selection.scope == 'device';
    _check(flow);
    return identity;
  }

  Future<AdbClient> _client(_SetupFlow flow) async {
    final selection = flow.identity!.selection;
    // 临时 PEM 的 SDK owner 必须先确认关闭，才能由 IdentityAttempt 删除该文件。
    if (selection.scope == 'device' && selection.deviceId == null) {
      flow.ephemeralIdentity = selection;
    }
    final client = await clientForIdentity(selection);
    _check(flow);
    return client;
  }

  Future<PairingReceipt> _pair(
    _SetupFlow flow,
    String address,
    int port,
    String code,
    SetupIdentity? identity,
  ) async {
    address = validateDeviceAddress(address);
    port = _port(port);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const RequestFailure('invalid_pairing_code', '请输入六位配对码。');
    }
    await _identity(flow, identity);
    final client = await _client(flow);
    final guid = await client.pair(
      _endpoint(address, port),
      code,
      timeout: policy.pairingTimeout,
      cancellation: flow.stop,
    );
    return _paired(flow, guid, address);
  }

  Future<PairingReceipt> _qr(
    _SetupFlow flow,
    SetupIdentity? identity,
    String instance,
    String password,
  ) async {
    await _identity(flow, identity);
    final client = await _client(flow);
    while (true) {
      await _ready(flow);
      List<AdbDiscoveryEndpoint> found;
      try {
        found = await discovery.scan(
          cancellation: flow.stop,
          pairingInstance: instance,
        );
      } catch (error) {
        _check(flow);
        if (_code(error) != 'cancelled') rethrow;
        await _pause(flow, policy.setupPollInterval);
        continue;
      }
      _check(flow);
      final candidates = found.where(
        (item) =>
            item.kind == AdbDiscoveryKind.pairing && item.instance == instance,
      );
      Object? unreachable;
      for (final candidate in candidates) {
        if (!discovery.isCurrent(candidate)) continue;
        try {
          // 密码只交给实际握手；仅明确未到达对端的网络失败才尝试另一地址。
          final guid = await client.pair(
            _endpoint(candidate.address, candidate.port),
            password,
            timeout: policy.endpointTimeout,
            cancellation: flow.stop,
          );
          return await _paired(flow, guid, candidate.address);
        } catch (error) {
          _check(flow);
          if (!const {
            'unreachable',
            'connection_refused',
            'host_unreachable',
            'network_unreachable',
            'connect_timeout',
          }.contains(_code(error))) {
            rethrow;
          }
          unreachable = error;
        }
      }
      if (unreachable != null) throw unreachable;
      await _pause(flow, policy.setupPollInterval);
    }
  }

  Future<PairingReceipt> _paired(
    _SetupFlow flow,
    String guid,
    String address,
  ) async {
    flow.receipt = PairingReceipt(guid: guid, address: address);
    final saved = await devices.recordPairing(
      deviceId: flow.deviceId,
      guid: guid,
      address: address,
      identity: flow.identity!,
    );
    final receipt = PairingReceipt(guid: guid, address: address, device: saved);
    flow.receipt = receipt;
    _bind(flow, receipt.deviceId);
    if (flow.cancelled || _disposed) return receipt.copyWith(cancelled: true);
    final deadline = _now().add(policy.pairingDiscoveryTimeout);
    Object? failure;
    var changes = 0;
    while (_now().isBefore(deadline)) {
      try {
        await _ready(flow);
        final found = await discovery.scan(cancellation: flow.stop);
        _check(flow);
        for (final candidate in found.where(
          (item) =>
              item.kind == AdbDiscoveryKind.tlsConnect &&
              DeviceDiscovery.matchesGuid(item.instance, guid),
        )) {
          if (!discovery.isCurrent(candidate)) continue;
          final client = await _client(flow);
          var opened = false;
          try {
            final connected = await devices.admitSetupCandidate(
              deviceId: flow.deviceId,
              identity: flow.identity!,
              client: client,
              transport: DeviceTransport.tls,
              guid: guid,
              address: candidate.address,
              port: candidate.port,
              attemptId: flow.attempt,
              cancellation: flow.stop,
              checkCandidate: () {
                if (!discovery.isCurrent(candidate)) {
                  throw const RequestFailure(
                    'discovery_changed',
                    '发现端点已变化，请重新核验。',
                  );
                }
              },
              open: (client, stop) async {
                final device = await client.connect(
                  client.capabilities.forceTlsWithoutMdns
                      ? _endpoint(candidate.address, candidate.port)
                      : candidate.serviceName.replaceFirst(
                          RegExp(r'\.local\.?$'),
                          '',
                        ),
                  requireTls: true,
                  authorize: policy.requestAuthorization,
                  timeout: policy.endpointTimeout,
                  directOptions: client.capabilities.officialServer
                      ? null
                      : policy.directConnectOptions(burstMode: _burstMode()),
                  cancellation: stop,
                );
                opened = true;
                return device;
              },
            );
            return receipt.copyWith(
              device: connected.device,
              connection: connected,
            );
          } catch (error) {
            // 仅在拨号未交付连接且已确认回收后换址；核验及准入准备失败不重放。
            if (opened ||
                !const {
                  'unreachable',
                  'connection_refused',
                  'host_unreachable',
                  'network_unreachable',
                  'connect_timeout',
                  'handshake_timeout',
                  'timeout',
                  'io_error',
                  'disconnected',
                }.contains(_code(error))) {
              rethrow;
            }
            failure = error;
          }
        }
        if (failure != null) break;
        await _pause(flow, policy.setupPollInterval);
      } catch (error) {
        failure = error;
        if (flow.cancelled || _disposed) break;
        if (_code(error) == 'discovery_changed') {
          if (++changes >= policy.pairingDiscoveryRetries) break;
        } else if (_code(error) != 'cancelled') {
          break;
        }
      }
    }
    final current = devices
        .readDevices()
        .where((item) => item.id == flow.deviceId)
        .firstOrNull;
    return receipt.copyWith(
      device: current ?? receipt.device,
      cancelled: flow.cancelled,
      connectionPortRequired:
          !flow.cancelled &&
          (failure == null || _code(failure) == 'discovery_pending'),
      connectionFailure: failure == null
          ? null
          : SetupIssue(_code(failure), '$failure'),
    );
  }

  Future<UsbSetupResult> _usb(
    _SetupFlow flow,
    SetupIdentity? identity,
    String? requestedSerial,
    String? usbDeviceId,
    bool connect,
  ) async {
    await _identity(flow, identity);
    final authorized = flow.usbAccess = authorizeUsb == null
        ? null
        : await authorizeUsb!(
            UsbAuthorizationRequest(
              attemptId: flow.attempt,
              deviceId: flow.deviceId,
              serial: requestedSerial,
              usbDeviceId: usbDeviceId,
              connect: connect,
            ),
          );
    _check(flow);
    final usbSerial = authorized?.serial ?? requestedSerial;
    if (usbSerial != null &&
        (usbSerial.length > 256 ||
            usbSerial.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const RequestFailure('invalid_argument', 'USB 候选序列号无效。');
    }
    String? selector;
    final fd = authorized?.fd;
    if (fd == null) {
      final client = await _client(flow);
      if (client is! AdbTransportDiscovery) {
        throw const RequestFailure('usb_unsupported', '当前平台没有 USB 传输枚举能力。');
      }
      final attached = (await (client as AdbTransportDiscovery).transports(
        timeout: policy.discoveryTimeout,
        cancellation: flow.stop,
      )).where((item) => item.usbPath != null).toList();
      _check(flow);
      final selected = requestedSerial != null
          ? attached
                .where((item) => item.serial == requestedSerial)
                .singleOrNull
          : attached.length == 1
          ? attached.single
          : null;
      if (selected == null) {
        return UsbSetupResult.selectionRequired([
          for (final item in attached)
            UsbDeviceChoice(
              serial: item.serial,
              state: item.state,
              usbPath: item.usbPath,
              model: item.model,
              transportId: item.transportId,
            ),
        ]);
      }
      selector = selected.serial;
    }
    _check(flow);
    final serial = selector ?? usbSerial;
    if (flow.deviceId == null && serial != null && serial.isNotEmpty) {
      final matches = devices.records.current.devices
          .where((record) => record.serial == serial)
          .toList();
      if (matches.length > 1) {
        throw const RequestFailure(
          'usb_selection_required',
          '多条记录匹配 USB 序列号，请明确选择原设备。',
        );
      }
      if (matches.length == 1) {
        if (identity is DedicatedSetupIdentity) {
          throw const RequestFailure(
            'identity_read_only',
            '此 USB 设备已有记录，请在原记录中管理其授权身份。',
          );
        }
        // 枚举序列号只选择待核验记录；最终仍由原连接所有者探测真实 serial。
        if (flow.ephemeralIdentity case final candidate?) {
          await releaseIdentityClient(candidate);
          flow.ephemeralIdentity = null;
        }
        await flow.identity!.dispose();
        flow.identity = null;
        _bind(flow, matches.single.id);
        await _identity(flow);
      }
    }
    _check(flow);
    final receipt = await devices.admitSetupCandidate(
      deviceId: flow.deviceId,
      identity: flow.identity!,
      transport: DeviceTransport.usb,
      releasePlatformResources: authorized?.close,
      attemptId: flow.attempt,
      cancellation: flow.stop,
      open: (client, stop) async {
        if (fd != null) {
          if (client is! NativeAdbClient || !client.capabilities.androidUsbFd) {
            throw const RequestFailure(
              'usb_unsupported',
              '当前主控不支持 Android USB 授权描述符。',
            );
          }
          final attempt = flow.usbAttempt = client.beginUsbFdConnection(
            fd,
            usbSerial ?? '',
            authorize: policy.requestAuthorization,
            timeout: policy.connectTimeout,
            options: policy.directConnectOptions(burstMode: _burstMode()),
            cancellation: stop,
          );
          final device = await attempt.result;
          // 返回设备后由 DeviceConnectionPool 持有平台连接，失败候选也按同一退休流程回收。
          flow.usbAccess = null;
          return device;
        }
        return client.connect(
          selector!,
          authorize: policy.requestAuthorization,
          timeout: policy.connectTimeout,
          cancellation: stop,
        );
      },
    );
    _bind(flow, receipt.deviceId);
    return UsbSetupResult.connected(receipt);
  }

  Future<WirelessReceipt> _tcpip(
    _SetupFlow flow,
    String address,
    int port, {
    required String connectionId,
  }) async {
    final id = flow.deviceId;
    if (id == null) {
      throw const RequestFailure('invalid_argument', '缺少设备标识。');
    }
    await _identity(flow);
    final original = devices.requireConnection(id);
    final facts = await original.client.services.connectionFacts(
      original.device,
    );
    _check(flow);
    if (facts.connectionId != connectionId) {
      throw const RequestFailure('stale_connection', '目标设备连接已变化，请重新获取地址。');
    }
    final network = await devices.readNetwork(
      id,
      connectionId: facts.connectionId,
      cancellation: flow.stop,
    );
    _check(flow);
    if (!identical(devices.current(id), original) ||
        facts.closed ||
        facts.connectionId == null ||
        network.connectionId != facts.connectionId) {
      throw const RequestFailure('stale_connection', '目标设备连接已变化，请重新获取地址。');
    }
    address = validateDeviceAddress(address);
    final addresses = network.value.addresses;
    if (!addresses.any((item) => item.address == address)) {
      throw const RequestFailure('address_changed', '目标设备网络地址已变化，请重新选择。');
    }
    final serial = devices.records.current.find(id)?.serial;
    if (serial == null || serial.isEmpty) {
      throw const RequestFailure(
        'device_identity_unverified',
        '缺少原设备实际序列号，不能转换连接。',
      );
    }
    port = _port(port);
    await devices.retireForChange<void>(
      id,
      original,
      cancellation: flow.stop,
      change: (connection, stop) async {
        final response = await connection.client.services.tcpip(
          connection.device,
          port,
          timeout: policy.tcpipRestartTimeout,
          cancellation: stop,
        );
        if (utf8.decode(response, allowMalformed: false).trim() !=
            'restarting in TCP mode port: $port') {
          throw const RequestFailure(
            'wireless_setup_failed',
            '设备未确认在指定端口开启 IP 连接。',
          );
        }
        flow.receipt = WirelessReceipt(
          deviceId: id,
          address: address,
          port: port,
        );
      },
    );
    _check(flow);
    final deadline = _now().add(policy.tcpipReconnectTimeout);
    while (true) {
      await _ready(flow);
      try {
        final receipt = await devices.admitTcpipCandidate(
          deviceId: id,
          identity: flow.identity!,
          expectedSerial: serial,
          address: address,
          port: port,
          attemptId: flow.attempt,
          cancellation: flow.stop,
          open: (client, stop) => client.connect(
            _endpoint(address, port),
            authorize: policy.requestAuthorization,
            timeout: policy.tcpipAttemptTimeout,
            directOptions: client.capabilities.officialServer
                ? null
                : policy.directConnectOptions(burstMode: _burstMode()),
            cancellation: stop,
          ),
        );
        return WirelessReceipt(
          deviceId: id,
          address: address,
          port: port,
          connection: receipt,
        );
      } catch (error) {
        _check(flow);
        if (!const {
          'unreachable',
          'connection_refused',
          'host_unreachable',
          'network_unreachable',
          'connect_timeout',
          'handshake_timeout',
          'timeout',
          'io_error',
          'disconnected',
        }.contains(_code(error))) {
          rethrow;
        }
        if (!_now().isBefore(deadline)) {
          throw const RequestFailure('timeout', 'IP 监听已开启，但目标尚未连接，请核对地址和端口。');
        }
      }
      await _pause(flow, policy.tcpipRetryInterval);
    }
  }

  void _bind(_SetupFlow flow, String? id) {
    if (id == null || flow.hold != null) return;
    flow.deviceId = id;
    if ((_stops[id] ?? -1) > flow.revision) _cancel(flow);
    flow.hold = holdDevice?.call(id);
  }

  Future<void> _ready(_SetupFlow flow) async {
    _check(flow);
    while (isStateUnverified()) {
      await _pause(flow, policy.setupPollInterval);
    }
  }

  Future<void> _pause(_SetupFlow flow, Duration duration) async {
    await Future.any([_delay(duration), flow.stop.whenCancelled]);
    _check(flow);
  }

  void _check(_SetupFlow flow) {
    if (!_now().isBefore(flow.deadline)) _cancel(flow, expired: true);
    if (flow.expired) {
      throw const RequestFailure('expired', '本次连接流程已到期。');
    }
    if (_disposed || flow.cancelled) {
      throw const RequestFailure('cancelled', '本次连接流程已停止。');
    }
  }

  void _cancel(_SetupFlow flow, {bool expired = false}) {
    flow.expired |= expired;
    flow.stop.cancel();
    if (flow.usbRequested && cancelUsb != null && flow.usbCancel == null) {
      flow.usbCancel = _cancelPlatformUsb(flow);
      // 先登记错误处理；失败仍由 flow 持有，实际 drain 时重试。
      unawaited(
        flow.usbCancel!.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  Future<void> _cancelPlatformUsb(_SetupFlow flow) async {
    await cancelUsb!(flow.attempt);
  }

  Future<void> _drain(_SetupFlow flow) async {
    try {
      await flow.work;
    } catch (_) {
      // 执行失败由原请求或 QR 事件报告；这里只确认原任务退出并重试其清理。
    }
    await _cleanup(flow);
  }

  Future<void> _cleanup(_SetupFlow flow) {
    if (flow.cleaned) return Future.value();
    if (flow.cleaning case final pending?) return pending;
    final operation = () async {
      if (!flow.settled) throw StateError('不能在执行任务退出前删除候选身份。');
      if (flow.usbCancel case final cancellation?) {
        try {
          await cancellation;
        } catch (_) {
          await _cancelPlatformUsb(flow);
        }
        flow.usbCancel = null;
      }
      await flow.usbAttempt?.close();
      flow.usbAttempt = null;
      if (flow.usbAccess case final access?) {
        await access.close();
        flow.usbAccess = null;
      }
      if (flow.ephemeralIdentity case final identity?) {
        await releaseIdentityClient(identity);
        flow.ephemeralIdentity = null;
      }
      await flow.identity?.dispose();
      await flow.hold?.call();
      flow.hold = null;
      flow.cleaned = true;
      _flows.remove(flow);
    }();
    return flow.cleaning = operation.whenComplete(() {
      flow.cleaning = null;
    });
  }

  /// 用户停止全部连接时先撤销各设置意图，再等待真实握手与平台回收。
  /// 不关闭协调器，后续明确的手动操作可以建立新流程。
  Future<void> stopPending() {
    final flows = _flows.toList();
    for (final flow in flows) {
      _cancel(flow);
    }
    return Future.wait(flows.map(_drain));
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopPending();
    await discovery.close();
  }
}

String _code(Object error) => switch (error) {
  RequestFailure(:final code) ||
  AdbException(:final code) ||
  DeviceRecordsFailure(:final code) => code,
  _ => 'setup_failed',
};
String _endpoint(String address, int port) =>
    address.contains(':') ? '[$address]:$port' : '$address:$port';
int _port(Object? value) {
  if (value is! int || value < 1 || value > 65535) {
    throw const RequestFailure('invalid_port', '端口必须为 1 到 65535。');
  }
  return value;
}

final class _SetupFlow {
  _SetupFlow(
    this.attempt,
    this.deviceId,
    this.revision,
    this.deadline,
    this.dedicatedIdentity,
  );
  final String attempt;
  final int revision;
  final DateTime deadline;
  bool dedicatedIdentity;
  final stop = AdbCancellation();
  String? deviceId;
  UsbAccess? usbAccess;
  IdentityAttempt? identity;
  IdentitySelection? ephemeralIdentity;
  DeviceSetupReceipt? receipt;
  Timer? timer;
  Future<Object?>? work;
  NativeAdbConnectionAttempt? usbAttempt;
  Future<void>? usbCancel, cleaning;
  Future<void> Function()? hold;
  bool usbRequested = false;
  // 后继替换、用户停止和超时都撤销同一个 token；取消先于监听器回调生效。
  bool get cancelled => stop.isCancelled;
  bool expired = false, settled = false, cleaned = false;
}
