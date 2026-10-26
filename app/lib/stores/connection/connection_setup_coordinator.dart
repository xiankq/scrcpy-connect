import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/application_request.dart' show Json;
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/stores/connection/device_coordinator.dart';
import 'package:scrcpy_connect/stores/connection/device_discovery.dart';
import 'package:scrcpy_connect/stores/connection/identity_manager.dart';
import 'package:scrcpy_connect/models/device_record.dart';

/// 产品设置流程的唯一所有者；直接调用 Dart 能力并等待真实执行结束。
/// 配对信任、监听切换与连接交付是三个独立事实，取消不能抹去已发生的前两项。
class ConnectionSetupCoordinator {
  ConnectionSetupCoordinator({
    required this.devices,
    required this.discovery,
    required this.clientForIdentity,
    required this.releaseIdentityClient,
    required this.policy,
    required this.emit,
    this.authorizeUsb,
    this.releaseUsb,
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

  final DeviceCoordinator devices;
  final DeviceDiscovery discovery;
  final FutureOr<AdbClient> Function(IdentitySelection) clientForIdentity;
  final Future<void> Function(IdentitySelection) releaseIdentityClient;
  final ConnectionPolicy policy;
  final void Function(Json) emit;
  final Future<Json> Function(Json)? authorizeUsb;
  final Future<void> Function(Json)? releaseUsb, cancelUsb;
  final Future<void> Function() Function(String)? holdDevice;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  final Random _random;
  final bool Function() _burstMode;
  final _flows = <_SetupFlow>{};
  final _stops = <String, int>{};
  bool _disposed = false, _recovering = false;
  int _next = 0, _revision = 0;

  bool handles(String command) => const {
    'devices.discover',
    'devices.pair',
    'devices.pair.qr',
    'devices.usb',
    'devices.wireless',
  }.contains(command);

  /// 先同步撤准入，再等待真实任务；身份变更或删除记录不能越过迟到配对回执。
  Future<void> beforeRequest(String command, Json params) async {
    var id = params['deviceId'];
    final activity = params['activityId'];
    final connectionStop =
        command == 'activities.stop' &&
        activity is String &&
        activity.startsWith('connection:');
    if (command == 'activities.stop' && !connectionStop) return;
    if (connectionStop) id = activity.substring(11);
    if (id is String &&
        const {
          'devices.connect',
          'devices.configure',
          'devices.disconnect',
          'devices.forget',
          'activities.stop',
        }.contains(command)) {
      _stops[id] = ++_revision;
    }
    final affected = _flows.where((flow) {
      if (command == 'settings.import') return true;
      if (command.startsWith('identity.') && !command.endsWith('.get')) {
        return command.startsWith('identity.device.')
            ? flow.deviceId == id
            : !flow.dedicatedIdentity;
      }
      return const {
            'devices.cancel',
            'devices.connect',
            'devices.configure',
            'devices.disconnect',
            'devices.forget',
            'activities.stop',
          }.contains(command) &&
          (params['attemptId'] == flow.attempt ||
              id != null && id == flow.deviceId);
    }).toList();
    for (final flow in affected) {
      _cancel(flow);
    }
    await Future.wait(affected.map(_drain));
  }

  void handleEvent(Json event) {
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _recovering = true;
    } else if (event['type'] == 'state.resynced') {
      _recovering = false;
    } else if (event['type'] == 'connections.stopped') {
      for (final flow in _flows.toList()) {
        _cancel(flow);
      }
    }
  }

  Future<Json> request(String command, Json params) async {
    if (_disposed) {
      throw const ApplicationCommandException('disposed', '连接协调器已释放。');
    }
    if (!handles(command)) {
      throw const ApplicationCommandException('unknown_command', '未知连接流程。');
    }
    policy.validate();
    final requestedAttempt = params['attemptId'];
    if (requestedAttempt != null &&
        (requestedAttempt is! String ||
            requestedAttempt.isEmpty ||
            requestedAttempt.length > 256 ||
            requestedAttempt.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const ApplicationCommandException('invalid_argument', '连接尝试标识无效。');
    }
    final id = params['deviceId'];
    if (id != null && (id is! String || !validDeviceId(id))) {
      throw const ApplicationCommandException('invalid_device_id', '设备记录标识无效。');
    }
    final attempt =
        requestedAttempt as String? ??
        'setup-${_now().microsecondsSinceEpoch}-${_next++}';
    final flow = _SetupFlow(
      attempt,
      id as String?,
      _revision,
      _now().add(
        command == 'devices.pair.qr'
            ? policy.qrPairingTimeout
            : policy.setupLeaseTimeout,
      ),
      params['identity'] is Map &&
          (params['identity'] as Map)['scope'] == 'device',
    );
    final replaced = _flows
        .where(
          (old) => old.attempt == attempt || id != null && old.deviceId == id,
        )
        .toList();
    for (final old in replaced) {
      _cancel(old);
    }
    _flows.add(flow);
    flow.usbRequested = command == 'devices.usb';
    flow.timer = Timer(
      flow.deadline.difference(_now()),
      () => _cancel(flow, expired: true),
    );
    String? instance, password;
    if (command == 'devices.pair.qr') {
      instance = 'studio-${_secret(12)}';
      password = _secret(32);
    }
    flow.work = Future.sync(() async {
      try {
        await Future.wait(replaced.map(_drain));
        _bind(flow, flow.deviceId);
        _check(flow);
        final result = switch (command) {
          'devices.discover' => await _discover(flow),
          'devices.pair' => await _pair(flow, params),
          'devices.pair.qr' => await _qr(flow, params, instance!, password!),
          'devices.usb' => await _usb(flow, params),
          'devices.wireless' => await _tcpip(flow, params),
          _ => throw StateError('未分派的连接流程'),
        };
        flow.result = result;
        return result;
      } on AdbException catch (error, stack) {
        Error.throwWithStackTrace(
          ApplicationCommandException(error.code, error.message, {
            if (flow.result != null) 'result': flow.result,
          }),
          stack,
        );
      } on ApplicationCommandException catch (error, stack) {
        if (flow.result == null) rethrow;
        Error.throwWithStackTrace(
          ApplicationCommandException(error.code, error.message, {
            'result': flow.result,
            if (error.details != null) 'cause': error.details,
          }),
          stack,
        );
      } on DeviceRecordsFailure catch (error, stack) {
        Error.throwWithStackTrace(
          ApplicationCommandException(error.code, error.message, {
            ...error.details,
            if (flow.result != null) 'result': flow.result,
          }),
          stack,
        );
      } finally {
        flow.timer?.cancel();
        flow.settled = true;
        try {
          await _cleanup(flow);
        } catch (error, stack) {
          Error.throwWithStackTrace(
            ApplicationCommandException(
              'setup_cleanup_unconfirmed',
              '连接流程的资源尚未确认释放：$error',
              {if (flow.result != null) 'result': flow.result},
            ),
            stack,
          );
        }
      }
    });
    if (command != 'devices.pair.qr') return flow.work!;
    unawaited(_publishQr(flow));
    return {
      'attemptId': attempt,
      'payload': 'WIFI:T:ADB;S:$instance;P:$password;;',
      'expiresAt': flow.deadline.millisecondsSinceEpoch ~/ 1000,
    };
  }

  String _secret(int bytes) =>
      base64UrlEncode(List.generate(bytes, (_) => _random.nextInt(256)))
          .replaceAll('=', '');

  Future<void> _publishQr(_SetupFlow flow) async {
    Json data;
    try {
      final result = await flow.work!;
      data = {
        'status': result['paired'] == true ? 'paired' : 'cancelled',
        'result': result,
      };
    } catch (error) {
      final known = flow.result;
      final recordedPairing = flow.pairingRecorded;
      data = {
        'status': recordedPairing
            ? 'paired'
            : flow.expired
            ? 'expired'
            : flow.cancelled
            ? 'cancelled'
            : 'failed',
        'code': _code(error),
        'message': '$error',
        if (known != null)
          'result': {
            ...known,
            if (recordedPairing)
              'cleanupFailure': {'code': _code(error), 'message': '$error'},
          },
      };
    }
    if (!_disposed) {
      emit({
        'type': 'pairing.changed',
        'deviceId': ?flow.deviceId,
        'data': {'attemptId': flow.attempt, ...data},
      });
    }
  }

  Future<Json> _discover(_SetupFlow flow) async {
    final endpoints = await discovery.scan(cancellation: flow.stop);
    _check(flow);
    final grouped = <String, List<AdbDiscoveryEndpoint>>{};
    for (final endpoint in endpoints) {
      grouped.putIfAbsent(endpoint.serviceName, () => []).add(endpoint);
    }
    return {
      'manualConnectionAvailable': true,
      'devices': [
        for (final group in grouped.values) _discoveredService(group),
      ],
    };
  }

  Json _discoveredService(List<AdbDiscoveryEndpoint> endpoints) {
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
    return {
      'kind': switch (first.kind) {
        AdbDiscoveryKind.pairing => 'pairing',
        AdbDiscoveryKind.tlsConnect => 'tls',
        AdbDiscoveryKind.tcpConnect => 'tcp',
      },
      'instance': first.instance,
      'name': first.instance,
      'fullname': first.serviceName,
      'hostname': first.hostname,
      'endpoints': [
        for (final endpoint in endpoints)
          {'address': endpoint.address, 'port': endpoint.port},
      ],
      'trusted': matches.length == 1,
      if (matches.length == 1) 'deviceId': matches.single.id,
    };
  }

  Future<IdentityAttempt> _identity(_SetupFlow flow, Json params) async {
    final identity = await devices.identities.prepareSetup(
      params,
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

  Future<Json> _pair(_SetupFlow flow, Json params) async {
    final address = validateDeviceAddress(params['address'] ?? params['host']);
    final port = _port(params['port']);
    final code = params['code'];
    if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const ApplicationCommandException(
        'invalid_pairing_code',
        '请输入六位配对码。',
      );
    }
    await _identity(flow, params);
    final client = await _client(flow);
    final guid = await client.pair(
      _endpoint(address, port),
      code,
      timeout: policy.pairingTimeout,
      cancellation: flow.stop,
    );
    return _paired(flow, guid, address);
  }

  Future<Json> _qr(
    _SetupFlow flow,
    Json params,
    String instance,
    String password,
  ) async {
    await _identity(flow, params);
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

  Future<Json> _paired(_SetupFlow flow, String guid, String address) async {
    // SDK 取得 GUID 后即有真实信任；先保存事实，再响应用户取消后续连接的意图。
    flow.result = {
      'paired': true,
      'connected': false,
      'guid': guid,
      'address': address,
    };
    final receipt = Map<String, dynamic>.from(
      await devices.recordPairing(
        deviceId: flow.deviceId,
        guid: guid,
        address: address,
        identity: flow.identity!,
      ),
    );
    flow.result = receipt;
    flow.pairingRecorded = true;
    _bind(flow, receipt['deviceId'] as String);
    if (flow.cancelled || _disposed) return {...receipt, 'cancelled': true};
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
                  throw const ApplicationCommandException(
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
            return {...receipt, ...connected, 'paired': true};
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
    return {
      ...receipt,
      'connected': false,
      'device':
          devices
              .projectDevices()
              .where((item) => item['id'] == flow.deviceId)
              .firstOrNull ??
          receipt['device'],
      'connectionPortRequired':
          !flow.cancelled &&
          (failure == null || _code(failure) == 'discovery_pending'),
      if (flow.cancelled) 'cancelled': true,
      if (failure != null)
        'connectionFailure': {'code': _code(failure), 'message': '$failure'},
    };
  }

  Future<Json> _usb(_SetupFlow flow, Json params) async {
    await _identity(flow, params);
    var authorized = params;
    if (!params.containsKey('fd') && authorizeUsb != null) {
      authorized = {
        ...params,
        ...await authorizeUsb!({...params, 'attemptId': flow.attempt}),
      };
    }
    if (authorized['usbLeaseId'] case final String lease) flow.usbLease = lease;
    _check(flow);
    final usbSerial = authorized['serial'];
    if (usbSerial != null &&
        (usbSerial is! String ||
            usbSerial.length > 256 ||
            usbSerial.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const ApplicationCommandException(
        'invalid_argument',
        'USB 候选序列号无效。',
      );
    }
    String? selector;
    final fd = authorized['fd'];
    if (fd != null && flow.usbLease == null ||
        fd == null && flow.usbLease != null) {
      throw const ApplicationCommandException(
        'invalid_argument',
        'USB 描述符与平台租约必须同时交付。',
      );
    }
    if (fd == null) {
      final client = await _client(flow);
      if (client is! AdbTransportDiscovery) {
        throw const ApplicationCommandException(
          'usb_unsupported',
          '当前平台没有 USB 传输枚举能力。',
        );
      }
      final attached = (await (client as AdbTransportDiscovery).transports(
        timeout: policy.discoveryTimeout,
        cancellation: flow.stop,
      )).where((item) => item.usbPath != null).toList();
      _check(flow);
      final requested = params['serial'];
      final selected = requested is String
          ? attached.where((item) => item.serial == requested).singleOrNull
          : attached.length == 1
          ? attached.single
          : null;
      if (selected == null) {
        return {
          'selectionRequired': true,
          'devices': [
            for (final item in attached)
              {
                'serial': item.serial,
                'state': item.state,
                'usbPath': item.usbPath,
                'model': item.model,
                'transportId': item.transportId,
              },
          ],
        };
      }
      selector = selected.serial;
    } else if (fd is! int || fd < 0) {
      throw const ApplicationCommandException(
        'invalid_argument',
        'USB 授权描述符无效。',
      );
    }
    _check(flow);
    final serial = selector ?? authorized['serial'];
    if (flow.deviceId == null && serial is String && serial.isNotEmpty) {
      final matches = devices.records.current.devices
          .where((record) => record.serial == serial)
          .toList();
      if (matches.length > 1) {
        throw const ApplicationCommandException(
          'usb_selection_required',
          '多条记录匹配 USB 序列号，请明确选择原设备。',
        );
      }
      if (matches.length == 1) {
        if (params['identity'] is Map &&
            (params['identity'] as Map)['scope'] == 'device') {
          throw const ApplicationCommandException(
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
        await _identity(flow, {});
      }
    }
    _check(flow);
    final platformLease = flow.usbLease;
    if (platformLease != null && releaseUsb == null) {
      throw const ApplicationCommandException(
        'usb_cleanup_unavailable',
        '缺少平台 USB 连接回收入口。',
      );
    }
    final receipt = await devices.admitSetupCandidate(
      deviceId: flow.deviceId,
      identity: flow.identity!,
      transport: DeviceTransport.usb,
      releasePlatformResources: platformLease == null
          ? null
          : () => releaseUsb!({'usbLeaseId': platformLease}),
      attemptId: flow.attempt,
      cancellation: flow.stop,
      open: (client, stop) async {
        if (fd != null) {
          if (client is! NativeAdbClient || !client.capabilities.androidUsbFd) {
            throw const ApplicationCommandException(
              'usb_unsupported',
              '当前主控不支持 Android USB 授权描述符。',
            );
          }
          final attempt = flow.usbAttempt = client.beginUsbFdConnection(
            fd as int,
            authorized['serial'] as String? ?? '',
            authorize: policy.requestAuthorization,
            timeout: policy.connectTimeout,
            options: policy.directConnectOptions(burstMode: _burstMode()),
            cancellation: stop,
          );
          final device = await attempt.result;
          // 返回设备后由 ConnectionOwner 持有平台连接，失败候选也按同一退休流程回收。
          flow.usbLease = null;
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
    _bind(flow, receipt['deviceId'] as String);
    return Map.from(receipt);
  }

  Future<Json> _tcpip(_SetupFlow flow, Json params) async {
    final id = flow.deviceId;
    if (id == null) {
      throw const ApplicationCommandException('invalid_argument', '缺少设备标识。');
    }
    await _identity(flow, params);
    final original = devices.requireConnection(id);
    final facts = await original.client.services.connectionFacts(
      original.device,
    );
    _check(flow);
    final network = await devices.command('device.network.get', {
      'deviceId': id,
      'connectionId': facts.connectionId,
    }, cancellation: flow.stop);
    _check(flow);
    if (!identical(devices.current(id), original) ||
        facts.closed ||
        facts.connectionId == null ||
        network['connectionId'] != facts.connectionId) {
      throw const ApplicationCommandException(
        'stale_connection',
        '目标设备连接已变化，请重新获取地址。',
      );
    }
    final address = validateDeviceAddress(params['address']);
    final addresses = network['addresses'] as List;
    if (!addresses.any((item) => item is Map && item['address'] == address)) {
      throw const ApplicationCommandException(
        'address_changed',
        '目标设备网络地址已变化，请重新选择。',
      );
    }
    final serial = devices.records.current.find(id)?.serial;
    if (serial == null || serial.isEmpty) {
      throw const ApplicationCommandException(
        'device_identity_unverified',
        '缺少原设备实际序列号，不能转换连接。',
      );
    }
    final port = _port(params['port'] ?? 5555);
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
          throw const ApplicationCommandException(
            'wireless_setup_failed',
            '设备未确认在指定端口开启 IP 连接。',
          );
        }
        flow.result = {
          'enabled': true,
          'connected': false,
          'deviceId': id,
          'port': port,
          'encrypted': false,
        };
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
        return {...receipt, 'enabled': true, 'port': port, 'encrypted': false};
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
          throw const ApplicationCommandException(
            'timeout',
            'IP 监听已开启，但目标尚未连接，请核对地址和端口。',
          );
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
    while (_recovering) {
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
      throw const ApplicationCommandException('expired', '本次连接流程已到期。');
    }
    if (_disposed || flow.cancelled) {
      throw const ApplicationCommandException('cancelled', '本次连接流程已停止。');
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
    await cancelUsb!({'attemptId': flow.attempt});
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
      if (flow.usbLease case final lease?) {
        if (releaseUsb == null) throw StateError('缺少 USB 授权回收入口。');
        await releaseUsb!({'usbLeaseId': lease});
        flow.usbLease = null;
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
  ApplicationCommandException(:final code) ||
  AdbException(:final code) ||
  DeviceRecordsFailure(:final code) => code,
  _ => 'setup_failed',
};
String _endpoint(String address, int port) =>
    address.contains(':') ? '[$address]:$port' : '$address:$port';
int _port(Object? value) {
  if (value is! int || value < 1 || value > 65535) {
    throw const ApplicationCommandException('invalid_port', '端口必须为 1 到 65535。');
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
  String? deviceId, usbLease;
  IdentityAttempt? identity;
  IdentitySelection? ephemeralIdentity;
  Json? result;
  Timer? timer;
  Future<Json>? work;
  NativeAdbConnectionAttempt? usbAttempt;
  Future<void>? usbCancel, cleaning;
  Future<void> Function()? hold;
  bool usbRequested = false;
  bool pairingRecorded = false;
  // 后继替换、用户停止和超时都撤销同一个 token；取消先于监听器回调生效。
  bool get cancelled => stop.isCancelled;
  bool expired = false, settled = false, cleaned = false;
}
