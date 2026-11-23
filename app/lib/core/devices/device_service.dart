import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_connection_pool.dart';
import 'package:scrcpy_connect/core/devices/device_details_reader.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_probe.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/adb_discovery_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

const _transientConnectionErrors = {
  'connection_refused',
  'network_unreachable',
  'host_unreachable',
  'connect_timeout',
  'handshake_timeout',
  'timeout',
  'connect_failed',
  'io_error',
  'disconnected',
};

String? _connectionErrorCode(Object error) => switch (error) {
  AdbException() => error.code,
  RequestFailure() => error.code,
  _ => null,
};

/// 设备记录、身份选择与实际连接的业务编排；不拥有 SDK 客户端或服务器。
/// 事件回调交给应用统一排序；本模块不创建另一条事件序列或持久记录。
final class DeviceService
    implements
        DeviceReader,
        DeviceManagement,
        DeviceInspection,
        DeviceConnectionControl {
  DeviceService({
    required this.records,
    required this.identities,
    required this.clientForIdentity,
    required this.prepareConnection,
    required Future<void> Function(String, DeviceConnection) stopActivities,
    this.policy = const ConnectionPolicy(),
    this.probe = const DeviceProbe(),
    this.reconnectionCandidates,
    bool Function()? burstMode,
    DateTime Function()? now,
    this.onChanged,
    this.onConnected,
  }) : _burstMode = burstMode ?? (() => false),
       _now = now ?? DateTime.now {
    _connections = DeviceConnectionPool(
      stopActivities: stopActivities,
      onDisconnected: (_, connection) {
        _officialEndpoints.release(connection);
        _facts.remove(connection);
      },
    );
  }

  final DeviceRecordStorage records;
  final AdbIdentityService identities;
  final FutureOr<AdbClient> Function(IdentitySelection) clientForIdentity;

  /// 身份已核验、旧连接与活动已退休后恢复候选所需状态；完成后才交付新连接。
  /// 失败不恢复旧活动，调用方须保留未确认恢复的精确责任，不自动重放操作。
  final Future<void> Function(
    String,
    DeviceConnection,
    String?,
    AdbCancellation,
  )
  prepareConnection;
  final ConnectionPolicy policy;
  final DeviceProbe probe;
  final DeviceReconnectionCandidates? reconnectionCandidates;
  final void Function(DeviceListChanged)? onChanged;

  /// 真实连接交付后登记监测；回调不得重新执行连接或发布候选。
  final void Function(String, DeviceConnection)? onConnected;
  late final DeviceConnectionPool _connections;
  late final _details = DeviceDetailsReader(
    records: records,
    connectionForDevice: current,
    now: _now,
  );
  final bool Function() _burstMode;
  final DateTime Function() _now;
  final _generations = <String, int>{};
  final _published = <String, DeviceConnection>{};
  final _facts = Map<DeviceConnection, AdbConnectionFacts>.identity();
  final _operations = <String, String>{};
  final _healthRetirements =
      Map<
        DeviceConnection,
        ({String deviceId, Future<void> Function() retry})
      >.identity();
  final _connecting = <String, int>{};
  final _endpointWrites = <String, int>{};
  final _officialEndpoints = _OfficialEndpoints();
  final _pending = <Future<Object?>>{};
  final _setupCreated = <String>{};
  Future<void> _setupTail = Future.value();
  bool _closed = false;
  Future<void>? _closing;
  Future<void>? _stopping;
  int _connectionEpoch = 0;
  _ReconnectLease? _reconnectLease;

  DeviceConnection? current(String id) {
    final published = _published[id];
    return published != null && identical(_connections.current(id), published)
        ? published
        : null;
  }

  DeviceConnection requireConnection(String id) =>
      current(id) ??
      (throw const RequestFailure('disconnected', '这台设备当前没有可用连接。'));

  /// 模式切换只借用已核验的精确旧连接；原端点与身份字段保持不变。
  /// 调用即撤准入，切换无论成败都收回原连接；失败清理沿既有退休队列重试。
  Future<T> retireForChange<T>(
    String id,
    DeviceConnection expected, {
    required Future<T> Function(DeviceConnection, AdbCancellation) change,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    _record(id);
    cancellation?.check();
    if (!identical(current(id), expected)) {
      _fail('stale_connection', '目标设备连接已变化。');
    }
    final generation = _next(id);
    _facts.remove(_published.remove(id));
    late final Future<void> projection;
    final retiring = _connections.retireForChange<T>(
      id,
      expected,
      cancellation: cancellation,
      change: (connection, stop) async {
        await projection;
        stop.check();
        return change(connection, stop);
      },
    );
    projection = records
        .update(id, (record) {
          // 后继配置或身份操作已经取得代次时，不再回写其连接状态。
          if (_generations[id] != generation) return record;
          return record.copyWith(
            status: 'offline',
            autoReconnect: false,
            reason: null,
          );
        })
        .then((_) => _changed());
    // 同时监听两条 Future；即使活动排空先失败，持久化失败也不会变成游离错误。
    return _track(
      Future.wait<Object?>([retiring, projection])
          .then((values) => values[0] as T),
    );
  }

  /// 记录真实配对回执；配对端口不属于连接端点，首次连接仍须独立核验。
  /// [identity] 由调用方持有，在整个设置流程退出后再 dispose。
  /// 不接收取消令牌：已知配对成功不能因用户停止后续连接而被当作未发生。
  Future<DeviceSnapshot> recordPairing({
    String? deviceId,
    required String guid,
    required String address,
    required IdentityAttempt identity,
  }) => _track(
    _serializeSetup(() async {
      _checkOpen();
      _validateGuid(guid);
      final host = validateDeviceAddress(address);
      await identities.validateSelection(
        identity.selection,
        deviceId: deviceId,
      );
      _checkOpen();
      final matches = records.current.devices.where(
        (record) => record.guid == guid,
      );
      final existing = deviceId != null
          ? _record(deviceId)
          : matches.firstOrNull;
      if (deviceId == null && matches.length > 1) {
        _fail('device_identity_mismatch', '此 GUID 对应多条记录，请明确选择原设备。');
      }
      if (existing != null) {
        if (existing.guid != null && existing.guid != guid) {
          _fail('device_identity_mismatch', '配对目标与原设备 GUID 不符。');
        }
        await identities.validateSelection(
          identity.selection,
          deviceId: existing.id,
        );
        final selected = await identities.selectForDevice(existing.id);
        if (selected.path != identity.selection.path ||
            selected.fingerprint != identity.selection.fingerprint) {
          _fail('identity_changed', '配对使用的身份不是原设备当前绑定的身份。');
        }
      }
      final record =
          existing ??
          await _createSetupRecord(
            identity: identity,
            address: host,
            transport: DeviceTransport.tls,
            guid: guid,
          );
      _checkOpen();
      await identities.validateSelection(
        identity.selection,
        deviceId: record.id,
      );
      _changed();
      return _snapshot(_record(record.id));
    }),
  );

  /// 接纳调用方明确选择的 USB 或 TLS 候选；不重新拨号旧记录端点。
  /// [open] 使用传入的实际客户端；返回前的清理由 SDK 负责，之后由 DeviceConnectionPool 精确回收。
  /// 新 USB 不传 [client]，在记录绑定身份后按持久路径取得客户端，不能捕获临时密钥路径。
  /// [checkCandidate] 在探测后、配置提交及交付前复核发现答案的当前代次。
  /// [releasePlatformResources] 只随实际返回的候选移交，SDK 断开成功后才调用。
  Future<DeviceConnectionReceipt> admitSetupCandidate({
    String? deviceId,
    required IdentityAttempt identity,
    AdbClient? client,
    required Future<AdbDevice> Function(AdbClient, AdbCancellation) open,
    required DeviceTransport transport,
    String address = '',
    int port = 0,
    String? guid,
    void Function()? checkCandidate,
    Future<void> Function()? releasePlatformResources,
    String? attemptId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    final epoch = _connectionEpoch;
    if (transport != DeviceTransport.usb && transport != DeviceTransport.tls) {
      _fail('invalid_transport', '设置候选仅支持 USB 或已配对 TLS。');
    }
    if (deviceId == null && client != null) {
      _fail('invalid_argument', '新设备须在绑定身份后取得客户端，不能预先指定临时身份客户端。');
    }
    if (transport == DeviceTransport.tls) {
      if (deviceId == null || guid == null || checkCandidate == null) {
        _fail('invalid_argument', 'TLS 候选需要原记录、配对 GUID 与代次核验。');
      }
      _validateGuid(guid);
      validateDeviceAddress(address);
      if (port < 1 || port > 65535) _fail('invalid_port', '连接端口无效。');
    }
    return _track(() async {
      final id =
          deviceId ??
          (await _serializeSetup(
            () => _createSetupRecord(
              identity: identity,
              address: '',
              transport: DeviceTransport.usb,
              cancellation: cancellation,
            ),
          )).id;
      if (epoch != _connectionEpoch) {
        _fail('cancelled', '本次设置连接已被宿主停止。');
      }
      return _connect(
        id,
        cancellation,
        configure: true,
        attemptId: attemptId,
        setup: _SetupCandidate(
          identity: identity,
          client: client,
          open: open,
          transport: transport,
          address: address,
          port: port,
          guid: guid,
          checkCandidate: checkCandidate,
          releasePlatformResources: releasePlatformResources,
          requireKnownSerial: !_setupCreated.contains(id),
        ),
      );
    }());
  }

  /// 只有显式监听转换流程可清除 TLS/GUID 并提交明文端点。
  /// [expectedSerial] 必须来自切换前真实连接的身份查询，不能用地址选择器代替。
  Future<DeviceConnectionReceipt> admitTcpipCandidate({
    required String deviceId,
    required String expectedSerial,
    required IdentityAttempt identity,
    AdbClient? client,
    required Future<AdbDevice> Function(AdbClient, AdbCancellation) open,
    required String address,
    required int port,
    String? attemptId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    final saved = _record(deviceId);
    if (expectedSerial.isEmpty || saved.serial != expectedSerial) {
      _fail('device_identity_unverified', 'TCP 转换缺少已核验的原设备序列号。');
    }
    validateDeviceAddress(address);
    if (port < 1 || port > 65535) _fail('invalid_port', '连接端口无效。');
    return _track(
      _connect(
        deviceId,
        cancellation,
        configure: true,
        attemptId: attemptId,
        setup: _SetupCandidate(
          identity: identity,
          client: client,
          open: open,
          transport: DeviceTransport.tcp,
          address: address,
          port: port,
          expectedSerial: expectedSerial,
          requireKnownSerial: true,
        ),
      ),
    );
  }

  Future<DeviceRecord> _createSetupRecord({
    required IdentityAttempt identity,
    required String address,
    required DeviceTransport transport,
    String? guid,
    AdbCancellation? cancellation,
  }) async {
    _checkOpen();
    cancellation?.check();
    await identities.validateSelection(identity.selection);
    _checkOpen();
    cancellation?.check();
    final record = await records.add(
      address: address,
      port: 0,
      transport: transport,
      guid: guid,
    );
    // 身份绑定失败不删除已提交记录或重放密钥事务，恢复交给 AdbIdentityService。
    await identity.bindNew(record.id);
    _setupCreated.add(record.id);
    cancellation?.check();
    _checkOpen();
    return _record(record.id);
  }

  Future<T> _serializeSetup<T>(Future<T> Function() action) {
    final result = _setupTail.then((_) => action());
    _setupTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// 只有本所有者实际交付的连接可以投影为已连接；磁盘缓存不能证明连接存活。
  @override
  List<DeviceSnapshot> readDevices() {
    _checkOpen();
    return [for (final record in records.current.devices) _snapshot(record)];
  }

  @override
  DeviceSnapshot readDevice(String id) {
    _checkOpen();
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    return _snapshot(_record(id));
  }

  @override
  Future<void> renameDevice(String id, String name) =>
      _track(_renameDevice(id, name));

  Future<void> _renameDevice(String id, String name) async {
    _checkOpen();
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    _record(id);
    await records.rename(id, validateDeviceName(name));
    _changed();
  }

  DeviceSnapshot _snapshot(DeviceRecord record) {
    final connection = current(record.id);
    final facts = _facts[connection];
    final status =
        connection == null &&
            (record.status == 'connected' ||
                !_connecting.containsKey(record.id) &&
                    (record.status == 'connecting' ||
                        record.status == 'authorizing'))
        ? DeviceConnectionStatus.offline
        : DeviceConnectionStatus.values.byName(record.status);
    return DeviceSnapshot.fromRecord(
      record,
      status: status,
      connectionId: connection != null && facts != null && !facts.closed
          ? facts.connectionId
          : null,
    );
  }

  @override
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) {
    _checkOpen(cancellation);
    return _track(
      _connect(
        deviceId,
        cancellation,
        configure: false,
        attemptId: attemptId,
        candidateSource: candidateSource,
      ),
    );
  }

  @override
  Future<DeviceConnectionReceipt> configureDevice(
    String deviceId,
    DeviceEndpoint endpoint, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) {
    _checkOpen(cancellation);
    return _track(
      _connect(
        deviceId,
        cancellation,
        configure: true,
        endpoint: endpoint,
        attemptId: attemptId,
        candidateSource: candidateSource,
      ),
    );
  }

  Future<void> connectAutomatically(
    String deviceId,
    String attemptId,
    String ownerId, {
    AdbCancellation? cancellation,
  }) async {
    _checkOpen(cancellation);
    await _track(
      _connect(
        deviceId,
        cancellation,
        configure: false,
        attemptId: attemptId,
        automaticOwnerId: ownerId,
      ),
    );
  }

  @override
  Future<void> cancelConnectionAttempt(String attemptId) {
    _checkOpen();
    return _track(_cancelTarget(attemptId));
  }

  @override
  Future<void> disconnectDevice(String id) =>
      _track(_stopDevice(id, forget: false));
  @override
  Future<void> forgetDevice(String id) => _track(_stopDevice(id, forget: true));

  Future<void> _stopDevice(String id, {required bool forget}) async {
    _checkOpen();
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    if (!forget) _record(id);
    await _disconnect(id, forget: forget);
  }

  Future<void> _cancelTarget(String target) async {
    final id = _operations[target] ?? target;
    if (records.current.find(id) != null) await _disconnect(id);
  }

  void setReconnectOwner(String id, bool active) {
    _checkOpen();
    if (id.isEmpty || id.length > 200 || id.contains('\x00')) {
      _fail('invalid_argument', '重连协调器标识无效。');
    }
    final previous = _reconnectLease;
    if (active && previous?.id != id) {
      // 先撤旧准入；取消监听中的重入请求只能观察到后继租约。
      _reconnectLease = _ReconnectLease(id);
      previous?.cancellation.cancel();
    } else if (!active && previous?.id == id) {
      _reconnectLease = null;
      previous!.cancellation.cancel();
    }
  }

  @override
  Future<DeviceReading<DeviceDetails>> readDetails(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readDetails(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<DeviceReading<DeviceBattery>> readBattery(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readBattery(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<DeviceReading<DeviceCapacity>> readSharedStorageCapacity(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readSharedStorageCapacity(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readNetwork(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<DeviceReading<DeviceScreenState>> readScreenState(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readScreenState(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<DeviceReading<String>> readForegroundApp(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    return _track(
      _details.readForegroundApp(
        deviceId,
        connectionId: connectionId,
        cancellation: cancellation,
      ),
    );
  }

  Future<T> _track<T>(Future<T> pending) {
    final operation = pending.onError<AdbException>((error, stack) {
      // 应用消费者读取 RequestFailure 的错误码；保留 SDK 的具体事实及原始堆栈。
      // AdbException 没有 details 字段，未知 Object 不经过此类型化映射。
      Error.throwWithStackTrace(
        RequestFailure(
          error.code,
          error.message.isNotEmpty
              ? error.message
              : error.code == 'cancelled'
              ? '本次设备操作已取消。'
              : 'ADB 操作未完成，请核对设备连接。',
        ),
        stack,
      );
    });
    _pending.add(operation);
    // 只登记真实运行的 Future；观察清理不能产生无人接收的失败 Future。
    unawaited(
      operation.then<void>(
        (_) => _pending.remove(operation),
        onError: (Object _, StackTrace _) => _pending.remove(operation),
      ),
    );
    return operation;
  }

  @override
  Future<DeviceSnapshot> addDevice(
    DeviceEndpoint endpoint, {
    String name = 'Android 设备',
    SetupIdentity? identity,
    AdbCancellation? cancellation,
  }) {
    _checkOpen(cancellation);
    return _track(_addDevice(endpoint, name, identity, cancellation));
  }

  Future<DeviceSnapshot> _addDevice(
    DeviceEndpoint endpoint,
    String name,
    SetupIdentity? selection,
    AdbCancellation? cancellation,
  ) async {
    endpoint = _validateEndpoint(endpoint);
    final identity = await identities.prepareSetup(identity: selection);
    try {
      cancellation?.check();
      _checkOpen();
      final record = await records.add(
        address: endpoint.address,
        port: endpoint.port,
        transport: endpoint.transport,
        name: validateDeviceName(name),
      );
      // 绑定失败保留记录供身份事务恢复，不回放密钥发布。
      await identity.bindNew(record.id);
      cancellation?.check();
      _checkOpen();
      _changed();
      return _snapshot(_record(record.id));
    } finally {
      await identity.dispose();
    }
  }

  @override
  Future<DeviceSnapshot> updateDeviceEndpoint(
    String id,
    DeviceEndpoint endpoint, {
    AdbCancellation? cancellation,
  }) {
    _checkOpen(cancellation);
    return _track(_updateDeviceEndpoint(id, endpoint));
  }

  Future<DeviceSnapshot> _updateDeviceEndpoint(
    String id,
    DeviceEndpoint endpoint,
  ) async {
    endpoint = _validateEndpoint(endpoint);
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    _record(id);
    _requireOfflineEndpoint(id);
    var writing = false;
    late final DeviceRecord record;
    try {
      record = await records.update(id, (old) {
        // 排队期间可能已开始连接；真正提交后则拒绝新连接使用尚未发布的旧端点。
        _requireOfflineEndpoint(id);
        writing = true;
        _endpointWrites[id] = (_endpointWrites[id] ?? 0) + 1;
        return _configured(old, endpoint);
      });
    } finally {
      if (writing) {
        final remaining = _endpointWrites[id]! - 1;
        if (remaining == 0) {
          _endpointWrites.remove(id);
        } else {
          _endpointWrites[id] = remaining;
        }
      }
    }
    _changed();
    return _snapshot(record);
  }

  void _requireOfflineEndpoint(String id) {
    if (current(id) != null || _connecting.containsKey(id)) {
      _fail('device_busy', '设备连接期间请使用连接配置核验流程。');
    }
  }

  Future<DeviceConnectionReceipt> _connect(
    String id,
    AdbCancellation? cancellation, {
    required bool configure,
    DeviceEndpoint? endpoint,
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    String? automaticOwnerId,
    _SetupCandidate? setup,
  }) async {
    if (_stopping != null) _fail('cancelled', '宿主正在停止设备连接，请在清理完成后重试。');
    if (!validDeviceId(id)) _fail('invalid_device_id', '设备标识无效。');
    final saved = _record(id);
    final automatic = automaticOwnerId != null;
    final lease = automatic ? _reconnectLease : null;
    if (automatic && (lease == null || lease.id != automaticOwnerId)) {
      _fail('reconnect_owner_required', '自动重连协调器已释放或尚未取得租约。');
    }
    if (automatic &&
        (configure || !policy.reconnectEnabled || !saved.autoReconnect)) {
      _fail('cancelled', '此设备已停止自动连接。');
    }
    if (_endpointWrites.containsKey(id)) {
      _fail('device_busy', '设备连接配置正在保存，请稍后重试。');
    }
    final discover =
        setup == null &&
        (!configure || candidateSource == .discovery) &&
        saved.transport == DeviceTransport.tls &&
        (saved.guid != null || saved.port == 0);
    if (candidateSource == .discovery && !discover) {
      _fail('discovery_unavailable', '只有已保存可信 GUID 的无线设备可使用发现候选。');
    }
    final target = setup != null
        ? saved.copyWith(
            address: setup.address,
            port: setup.port,
            transport: setup.transport,
            guid: setup.transport == DeviceTransport.usb
                ? saved.guid
                : setup.guid,
          )
        : configure
        ? _configured(saved, _validateEndpoint(endpoint!))
        : saved;
    if (setup?.guid case final guid?) {
      if (saved.guid != null && saved.guid != guid) {
        _fail('device_identity_mismatch', '发现候选的 GUID 与原设备不符。');
      }
    }
    if (setup == null && target.transport == DeviceTransport.usb) {
      _fail('usb_permission_required', 'USB 连接须通过平台设备选择与授权流程。');
    }
    if (!discover &&
        target.transport != DeviceTransport.usb &&
        (target.port == 0 || target.address.isEmpty)) {
      _fail('discovery_required', '此记录需要先发现当前无线连接端点。');
    }
    if (!configure) {
      if (current(id) case final existing?) return _connected(id, existing);
    }
    final alias = attemptId;
    if (alias != null && (alias.isEmpty || alias.length > 200 || alias == id)) {
      _fail('invalid_attempt_id', '连接尝试标识无效。');
    }
    if (alias != null && _operations.containsKey(alias)) {
      _fail('attempt_in_use', '此连接尝试标识仍在使用。');
    }
    final generation = _next(id);
    _connecting[id] = generation;
    if (alias != null) _operations[alias] = id;
    void Function()? detachLease;
    void Function()? detachExternal;
    if (lease != null) {
      final external = cancellation;
      final linked = cancellation = AdbCancellation();
      detachLease = lease.cancellation.onCancel(linked.cancel);
      detachExternal = external?.onCancel(linked.cancel);
    }
    AdbCancellation? activeStop;
    DeviceConnection? candidate;
    Future<void>? cancellationCleanup;
    final detach = cancellation?.onCancel(() {
      if (_generations[id] == generation) {
        try {
          activeStop?.cancel();
        } finally {
          if (candidate case final delivered?) {
            // 已交付后取消也同步撤准入，重入的后继请求不能复用它。
            cancellationCleanup ??= _connections.release(id, delivered);
            cancellationCleanup!.ignore();
          }
        }
      }
    });
    AdbConnectionFacts? verifiedFacts;
    String? observedSerial;
    var preparationFailed = false;
    void Function()? releaseDialing;
    DeviceRecord? previousEndpoint;
    final candidates = _ConnectionCandidates(
      saved: saved,
      target: target,
      discover: discover,
      resolver: reconnectionCandidates,
      discoveryOnly: candidateSource == .discovery,
    );
    final updatesEndpoint = configure || discover;
    void checkCandidate() {
      setup?.checkCandidate?.call();
      candidates.checkCurrent();
    }

    try {
      final selection =
          setup?.identity.selection ?? await identities.selectForDevice(id);
      await identities.validateSelection(selection, deviceId: id);
      final selected = await identities.selectForDevice(id);
      if (selected.path != selection.path ||
          selected.fingerprint != selection.fingerprint) {
        _fail('identity_changed', '设置候选没有使用设备当前绑定的身份。');
      }
      _check(id, generation, cancellation);
      final client = setup?.client ?? await clientForIdentity(selection);
      _check(id, generation, cancellation);
      if (!configure) {
        _published.remove(id);
        await records.update(id, (record) {
          _check(id, generation, cancellation);
          return record.copyWith(status: 'connecting', reason: null);
        });
        _changed();
      }
      _check(id, generation, cancellation);
      Future<DeviceConnection> open(AdbCancellation stop) async {
        activeStop = stop;
        _check(id, generation, cancellation);
        await identities.validateSelection(selection, deviceId: id);
        stop.check();
        await candidates.resolve(client, stop);
        stop.check();
        _check(id, generation, cancellation);
        candidates.chooseEndpoint();
        checkCandidate();
        if (client.capabilities.officialServer &&
            candidates.target.transport != DeviceTransport.usb) {
          releaseDialing = _officialEndpoints.reserve(
            client,
            _address(candidates.target),
          );
        }
        // open 成功后只包装精确资源并交回所有者，不在登记前等待或检查取消。
        // 迟到候选的取消和核验失败均由 DeviceConnectionPool 先断开传输、后回收平台租约。
        final connection = DeviceConnection(
          client: client,
          releasePlatformResources: setup?.releasePlatformResources,
          device: setup != null
              ? await setup.open(client, stop)
              : await client.connect(
                  candidates.endpoint != null &&
                          !client.capabilities.forceTlsWithoutMdns
                      ? candidates.endpoint!.serviceName.replaceFirst(
                          RegExp(r'\.local\.?$'),
                          '',
                        )
                      : _address(candidates.target),
                  requireTls:
                      candidates.target.transport == DeviceTransport.tls ||
                      candidates.target.guid != null,
                  authorize: policy.requestAuthorization,
                  timeout: discover
                      ? policy.endpointTimeout
                      : policy.connectTimeout,
                  directOptions: client.capabilities.officialServer
                      ? null
                      : policy.directConnectOptions(burstMode: _burstMode()),
                  cancellation: stop,
                ),
        );
        if (client.capabilities.officialServer &&
            candidates.target.transport != DeviceTransport.usb) {
          _officialEndpoints.register(connection, _address(candidates.target));
        }
        return connection;
      }

      Future<void> verify(
        DeviceConnection connection,
        AdbCancellation stop,
      ) async {
        final observed = await probe.readIdentity(
          connection,
          cancellation: stop,
          timeout: policy.probeTimeout,
        );
        observed.assertMatches(
          saved,
          requireKnownSerial: setup?.requireKnownSerial ?? configure,
        );
        if (setup?.expectedSerial case final serial?) {
          if (observed.serial != serial) {
            _fail('device_identity_mismatch', 'TCP 候选不是切换前已核验的设备。');
          }
        }
        if (setup?.guid case final guid?) {
          if (observed.guid != guid) {
            _fail('device_identity_mismatch', 'TLS 候选没有返回本次配对的真实 GUID。');
          }
        }
        if (candidates.target.transport == DeviceTransport.tls &&
            saved.guid != null &&
            observed.guid != saved.guid) {
          _fail('device_identity_mismatch', 'TLS 候选没有返回原设备的真实 GUID。');
        }
        checkCandidate();
        await identities.validateSelection(selection, deviceId: id);
        final facts = await client.services.connectionFacts(connection.device);
        stop.check();
        _check(id, generation, cancellation);
        if (facts.closed || facts.connectionId == null) {
          _fail('disconnected', '候选连接已关闭或缺少实际连接身份。');
        }
        if (facts.configuredIdentity case final configured?) {
          if (configured.fingerprint != selection.fingerprint) {
            _fail('identity_changed', '此连接配置的密钥与本次选择不符。');
          }
        }
        verifiedFacts = facts;
        observedSerial = observed.serial;
        // 写入失败时 DeviceConnectionPool 仍持有候选，负责精确回收；尚未发布业务成功。
        await records.update(id, (record) {
          stop.check();
          _check(id, generation, cancellation);
          checkCandidate();
          if (updatesEndpoint) {
            // 只保存本次实际提交所依据的端点，不回放旧名称、身份或其他字段。
            previousEndpoint = record;
          }
          return (updatesEndpoint
                  ? record.copyWith(
                      address: candidates.target.address,
                      port: candidates.target.port,
                      transport: candidates.target.transport,
                      guid: setup != null
                          ? candidates.target.guid
                          : record.guid,
                    )
                  : record)
              .copyWith(
                status: 'connected',
                serial: observed.serial ?? record.serial,
                model: observed.model ?? record.model,
                androidVersion:
                    observed.androidVersion ?? record.androidVersion,
                apiLevel: observed.apiLevel ?? record.apiLevel,
                name: record.name == 'Android 设备'
                    ? observed.model ?? record.name
                    : record.name,
                reason: null,
                battery: null,
                charging: null,
                batteryUpdatedAt: null,
                autoReconnect: true,
                lastSeen: _now().millisecondsSinceEpoch ~/ 1000,
              );
        });
        stop.check();
        await identities.validateSelection(selection, deviceId: id);
        _check(id, generation, cancellation);
        checkCandidate();
      }

      Future<void> restoreRejectedConfiguration(DeviceConnection _) async {
        final previous = previousEndpoint;
        if (previous == null) return;
        final unchanged = Object();
        try {
          await records.update(id, (latest) {
            if (latest.address != candidates.target.address ||
                latest.port != candidates.target.port ||
                latest.transport != candidates.target.transport ||
                setup != null && latest.guid != candidates.target.guid) {
              // Store 的普通 update 即使值不变也会提交；在其串行读取内退出，
              // 避免原提交失败或端点已被别人修改时再发起一次无意义写入。
              throw unchanged;
            }
            return latest.copyWith(
              address: previous.address,
              port: previous.port,
              transport: previous.transport,
              guid: setup != null ? previous.guid : latest.guid,
            );
          });
        } catch (error) {
          if (!identical(error, unchanged) &&
              !(error is DeviceRecordsFailure && error.code == 'not_found')) {
            rethrow;
          }
          // 已删除或已改变端点的记录不再承担补偿，不能重建它或恢复旧身份绑定。
        }
        previousEndpoint = null;
      }

      Future<void> beforeAdmit(
        DeviceConnection connection,
        AdbCancellation stop,
      ) async {
        try {
          stop.check();
          _check(id, generation, cancellation);
          checkCandidate();
          await identities.validateSelection(selection, deviceId: id);
          stop.check();
          _check(id, generation, cancellation);
          checkCandidate();
          await prepareConnection(id, connection, observedSerial, stop);
          stop.check();
          _check(id, generation, cancellation);
          checkCandidate();
          await identities.validateSelection(selection, deviceId: id);
          final facts = await client.services.connectionFacts(
            connection.device,
          );
          stop.check();
          _check(id, generation, cancellation);
          checkCandidate();
          if (facts.closed || facts.connectionId == null) {
            _fail('disconnected', '准入准备后候选连接已关闭或缺少实际连接身份。');
          }
          if (facts.configuredIdentity case final configured?) {
            if (configured.fingerprint != selection.fingerprint) {
              _fail('identity_changed', '准入准备后的连接密钥与本次选择不符。');
            }
          }
          verifiedFacts = facts;
        } catch (_) {
          // 此时旧活动已退休；远端恢复未确认不能因 timeout 等传输码换址重播。
          preparationFailed = true;
          rethrow;
        }
      }

      while (true) {
        try {
          candidate = updatesEndpoint
              ? await _connections.reconfigure(
                  id,
                  open: open,
                  verify: verify,
                  beforeAdmit: beforeAdmit,
                  onRejected: restoreRejectedConfiguration,
                )
              : await _connections.replace(
                  id,
                  open: open,
                  verify: verify,
                  beforeAdmit: beforeAdmit,
                );
          break;
        } catch (error) {
          if (preparationFailed) rethrow;
          final code = _connectionErrorCode(error);
          final retryable = _transientConnectionErrors.contains(code);
          // 未知清理与服务器未知状态必须原样交还，不能被取消或候选失效掩盖。
          if (!retryable && code != 'auth_failed') rethrow;
          _check(id, generation, cancellation);
          checkCandidate();
          if (!retryable || !candidates.hasNext) rethrow;
          // 所有者已经确认候选退出；未知清理不在重试集合中，不能换址重放。
          releaseDialing?.call();
          releaseDialing = null;
          candidates.advance();
          verifiedFacts = null;
        }
      }
      _check(id, generation, cancellation);
      checkCandidate();
      _facts.remove(_published[id]);
      _facts[candidate] = verifiedFacts!;
      _published[id] = candidate;
      _setupCreated.remove(id);
      onConnected?.call(id, candidate);
      _changed();
      _check(id, generation, cancellation);
      return _connected(id, candidate);
    } catch (error, stack) {
      Object? cleanupFailure;
      StackTrace? cleanupStack;
      if (candidate != null) {
        try {
          // replace 已交付后仍须核验应用取消；撤回只针对本候选，不影响后继尝试。
          await (cancellationCleanup ?? _connections.release(id, candidate));
        } catch (failure, trace) {
          cleanupFailure = failure;
          cleanupStack = trace;
        }
      }
      if (_generations[id] == generation && !_closed) {
        if (!configure || _connections.current(id) == null) {
          final code = _connectionErrorCode(error);
          final keepIntent =
              cleanupFailure == null &&
              (code == 'cancelled' ||
                  !preparationFailed &&
                      (_transientConnectionErrors.contains(code) ||
                          code == 'discovery_pending' ||
                          code == 'discovery_changed' ||
                          code == 'discovery_unavailable'));
          _facts.remove(_published.remove(id));
          await records.update(
            id,
            (record) => _generations[id] != generation || _closed
                ? record
                : record.copyWith(
                    status: code == 'auth_failed' ? 'unauthorized' : 'offline',
                    reason: error.toString(),
                    // 成功交付才启用意图；暂时断线或调度暂停保留原意图，
                    // 身份冲突及未知清理停止自动尝试，等待用户明确处理。
                    autoReconnect: keepIntent && saved.autoReconnect,
                  ),
          );
        }
        _changed();
      }
      if (cleanupFailure != null) {
        Error.throwWithStackTrace(
          RequestFailure(
            'connection_cleanup_unconfirmed',
            '业务接纳失败，精确连接尚未确认释放，请重试断开。',
            {'cause': '$cleanupFailure'},
          ),
          cleanupStack!,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      detach?.call();
      detachLease?.call();
      detachExternal?.call();
      if (_connecting[id] == generation) {
        _connecting.remove(id);
      }
      releaseDialing?.call();
      if (alias != null && _operations[alias] == id) {
        _operations.remove(alias);
      }
    }
  }

  DeviceConnectionReceipt _connected(String id, DeviceConnection connection) =>
      DeviceConnectionReceipt(
        device: _snapshot(_record(id)),
        adbBurstActive: _facts[connection]?.burstMode,
      );

  Future<void> _disconnect(String id, {bool forget = false}) async {
    final generation = _next(id);
    _facts.remove(_published.remove(id));
    final drain = _connections.disconnect(id);
    final projection = () async {
      if (records.current.find(id) != null) {
        await records.update(
          id,
          (record) => _generations[id] == generation
              ? record.copyWith(
                  status: 'offline',
                  autoReconnect: false,
                  reason: null,
                )
              : record,
        );
      }
      _changed();
    }();
    // 清理失败仍保存停止意图，重启不能复活；持久化失败也不能跳过实际资源回收。
    await Future.wait<void>([
      drain,
      projection,
      _retryHealthRetirements({id}),
    ]);
    if (_generations[id] != generation) _fail('cancelled', '停止已被后继连接操作替换。');
    if (forget && records.current.find(id) != null) await records.remove(id);
    if (forget) await identities.forgetDevice(id);
    if (forget) _setupCreated.remove(id);
    _changed();
  }

  /// 健康监测只退休仍为当前的精确连接，不撤销后继尝试或自动重连意图。
  /// 清理与离线投影分别保留重试责任；连接失效先同步撤准入，再等待实际释放。
  Future<void> retireUnhealthy(
    String id,
    DeviceConnection expected, {
    required String reason,
  }) {
    final previous = _healthRetirements[expected];
    if (previous != null) return _track(previous.retry());
    if (_closed || !identical(current(id), expected)) return Future.value();
    final generation = _next(id);
    _facts.remove(_published.remove(id));
    var projected = false;
    Future<void>? pending;
    late Future<void> Function() retry;
    retry = () => pending ??= (() async {
      // release 只按精确对象撤准入；后继即使已经进入队列也不会被本次健康判断撤销。
      final drain = _connections.release(id, expected);
      final projection = () async {
        if (projected) return;
        if (_closed || _generations[id] != generation) {
          projected = true;
          return;
        }
        if (records.current.find(id) != null) {
          await records.update(id, (record) {
            if (_closed || _generations[id] != generation) return record;
            return record.copyWith(status: 'offline', reason: reason);
          });
        }
        projected = true;
        _changed();
      }();
      await Future.wait<void>([drain, projection]);
      _healthRetirements.remove(expected);
    })().whenComplete(() => pending = null);
    _healthRetirements[expected] = (deviceId: id, retry: retry);
    return _track(retry());
  }

  Future<void> _retryHealthRetirements([Set<String>? ids]) =>
      Future.wait<void>([
        for (final retirement in _healthRetirements.values.toList())
          if (ids == null || ids.contains(retirement.deviceId))
            retirement.retry(),
      ]);

  /// 身份管理器可直接使用本方法；调用即撤销发布和所有在途应用代次。
  Future<void> invalidate(Iterable<String> ids) {
    final affected = ids.toSet();
    for (final id in affected) {
      _next(id);
      _facts.remove(_published.remove(id));
    }
    final drain = _connections.invalidate(affected);
    return Future.wait<void>([drain, _retryHealthRetirements(affected)]);
  }

  /// 宿主停止立即撤销全部连接准入，随后等待原活动、传输和平台租约实际退出。
  /// 不关闭本所有者；失败保留原退休责任，显式重试完成后仍允许手动连接。
  Future<void> stopConnections() {
    _checkOpen();
    if (_stopping case final pending?) return pending;
    final pendingOperations = _pending.toList();
    final completion = Completer<void>();
    final stopping = _stopping = _track(completion.future);
    _connectionEpoch++;
    final lease = _reconnectLease;
    _reconnectLease = null;
    final generations = <String, int>{
      for (final id in {
        ...records.current.devices.map((record) => record.id),
        ..._generations.keys,
      })
        id: _next(id),
    };
    for (final id in generations.keys) {
      _facts.remove(_published.remove(id));
    }
    final drain = _connections.invalidate(generations.keys);
    final projection = Future.wait([
      for (final entry in generations.entries)
        if (records.current.find(entry.key) != null)
          records.update(
            entry.key,
            (record) => _generations[entry.key] == entry.value
                ? record.copyWith(
                    status: 'offline',
                    autoReconnect: false,
                    reason: null,
                  )
                : record,
          ),
    ]).then<void>((_) => _changed());
    unawaited(
      Future.wait<void>([
        drain,
        projection,
        _retryHealthRetirements(generations.keys.toSet()),
        Future<void>.sync(() => lease?.cancellation.cancel()),
        for (final pending in pendingOperations)
          pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]).then<void>(
        (_) {
          if (identical(_stopping, stopping)) _stopping = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_stopping, stopping)) _stopping = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return stopping;
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    _reconnectLease = null;
    _published.clear();
    final drain = _connections.close();
    return _closing = (() async {
      try {
        await drain;
        await _retryHealthRetirements();
        await Future.wait([
          for (final pending in _pending.toList())
            pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ]);
        _facts.clear();
      } catch (_) {
        _closing = null;
        rethrow;
      }
    })();
  }

  int _next(String id) => _generations[id] = (_generations[id] ?? 0) + 1;
  void _checkOpen([AdbCancellation? cancellation]) {
    if (_closed) _fail('disposed', '设备协调器已关闭。');
    if (cancellation?.isCancelled == true) {
      _fail('cancelled', '本次设备操作已取消。');
    }
  }

  void _check(String id, int generation, AdbCancellation? cancellation) {
    _checkOpen();
    cancellation?.check();
    if (_generations[id] != generation) _fail('cancelled', '本次连接已失效。');
  }

  DeviceRecord _record(String id) =>
      records.current.find(id) ??
      (throw const RequestFailure('not_found', '这台设备的本机记录已不存在。'));
  void _changed() {
    if (!_closed) onChanged?.call(DeviceListChanged(readDevices()));
  }
}

/// 单次连接尝试的候选游标；只选择端点，不持有连接或修改设备记录。
final class _ConnectionCandidates {
  _ConnectionCandidates({
    required this.saved,
    required this.target,
    required this.discover,
    required this.resolver,
    required this.discoveryOnly,
  });

  final DeviceRecord saved;
  DeviceRecord target;
  final bool discover;
  final DeviceReconnectionCandidates? resolver;
  final bool discoveryOnly;
  List<AdbDiscoveryEndpoint>? _discovered;
  AdbDiscoveryEndpoint? endpoint;
  int _index = 0;
  bool _cachedAttempted = false;
  bool _discoveryAttempted = false;

  Future<void> resolve(AdbClient client, AdbCancellation stop) async {
    if (!discover) return;
    final guid = saved.guid;
    if (guid == null) {
      _fail('device_identity_unverified', '无线发现需要已保存的配对 GUID。');
    }
    if (!_cachedAttempted &&
        !_discoveryAttempted &&
        client.capabilities.forceTlsWithoutMdns &&
        saved.port > 0 &&
        saved.address.isNotEmpty &&
        !discoveryOnly) {
      // 缓存端点可以跨网直连；授权、真实 GUID 和应用代次仍须独立核验。
      _cachedAttempted = true;
      target = saved.copyWith(transport: DeviceTransport.tls);
      return;
    }
    _discoveryAttempted = true;
    final discovery = resolver;
    if (discovery == null) _fail('discovery_unavailable', '无线发现尚未配置。');
    _discovered ??= await discovery.resolve(guid, cancellation: stop);
  }

  /// 调用方先检查取消与代次，再让发现结果决定下一次拨号目标。
  void chooseEndpoint() {
    if (!_discoveryAttempted) return;
    if (_discovered!.isEmpty) {
      _fail('discovery_pending', '尚未发现这台已配对设备的当前连接端点。');
    }
    final selected = endpoint = _discovered![_index];
    if (selected.kind != AdbDiscoveryKind.tlsConnect ||
        !DeviceDiscovery.matchesGuid(selected.instance, saved.guid!)) {
      _fail('device_identity_mismatch', '发现候选不是原设备的 TLS 服务。');
    }
    target = saved.copyWith(
      address: selected.address,
      port: selected.port,
      transport: DeviceTransport.tls,
    );
  }

  void checkCurrent() {
    if (endpoint case final selected?) {
      if (!resolver!.isCurrent(selected)) {
        _fail('discovery_changed', '发现端点已变化，请重新核验。');
      }
    }
  }

  bool get _discoverAfterCache =>
      _cachedAttempted && !_discoveryAttempted && resolver != null;

  bool get hasNext =>
      discover &&
      (_discoverAfterCache ||
          _discovered != null && _index + 1 < _discovered!.length);

  /// 只在所有者确认本候选已回收、且主流程确认错误可重试后推进。
  void advance() {
    endpoint = null;
    if (!_discoverAfterCache) _index++;
  }
}

/// 官方客户端按端点复用底层资源；拨号与已交付连接必须共用占用账本。
final class _OfficialEndpoints {
  final _dialing = Map<AdbClient, Map<String, Object>>.identity();
  final _connections = Map<DeviceConnection, String>.identity();

  void Function() reserve(AdbClient client, String address) {
    final occupied = _connections.entries.any(
      (entry) => identical(entry.key.client, client) && entry.value == address,
    );
    final dialing = _dialing.putIfAbsent(client, () => {});
    if (occupied || dialing.containsKey(address)) {
      _fail('independent_connection_required', '同一官方 ADB 客户端的端点仍在使用，不能独立创建候选。');
    }
    final token = Object();
    dialing[address] = token;
    return () {
      // 迟到清理只能释放本次占用，不能移除后继拨号。
      if (identical(dialing[address], token)) dialing.remove(address);
      if (dialing.isEmpty && identical(_dialing[client], dialing)) {
        _dialing.remove(client);
      }
    };
  }

  void register(DeviceConnection connection, String address) =>
      _connections[connection] = address;

  // 撤准入或编辑记录不释放占用；只由实际断开成功的回执移除。
  void release(DeviceConnection connection) => _connections.remove(connection);
}

final class _ReconnectLease {
  _ReconnectLease(this.id);
  final String id;
  final cancellation = AdbCancellation();
}

final class _SetupCandidate {
  const _SetupCandidate({
    required this.identity,
    required this.client,
    required this.open,
    required this.transport,
    required this.address,
    required this.port,
    required this.requireKnownSerial,
    this.guid,
    this.expectedSerial,
    this.checkCandidate,
    this.releasePlatformResources,
  });
  final IdentityAttempt identity;
  final AdbClient? client;
  final Future<AdbDevice> Function(AdbClient, AdbCancellation) open;
  final DeviceTransport transport;
  final String address;
  final int port;
  final bool requireKnownSerial;
  final String? guid, expectedSerial;
  final void Function()? checkCandidate;
  final Future<void> Function()? releasePlatformResources;
}

void _validateGuid(String guid) {
  if (guid.isEmpty ||
      guid.length > 256 ||
      guid.runes.any((c) => c < 32 || c == 127)) {
    _fail('invalid_argument', '配对 GUID 无效。');
  }
}

DeviceEndpoint _validateEndpoint(DeviceEndpoint endpoint) {
  if (endpoint.transport != .tcp && endpoint.transport != .tls) {
    _fail('invalid_transport', '手动端点仅支持 TCP 或 TLS。');
  }
  if (recordInteger(endpoint.port, 'port', 65535) == 0) {
    _fail('invalid_port', '连接端口必须为 1 到 65535。');
  }
  return endpoint.copyWith(address: validateDeviceAddress(endpoint.address));
}

DeviceRecord _configured(DeviceRecord record, DeviceEndpoint endpoint) =>
    record.copyWith(
      address: endpoint.address,
      port: endpoint.port,
      transport: record.guid != null || record.transport == DeviceTransport.tls
          ? DeviceTransport.tls
          : endpoint.transport,
    );

String _address(DeviceRecord record) =>
    '${record.address.contains(':') ? '[${record.address}]' : record.address}:${record.port}';
Never _fail(String code, String message) => throw RequestFailure(code, message);
