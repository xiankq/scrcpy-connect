import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/media/physical_display_recovery.dart';
import 'package:scrcpy_connect/services/platform/bundled_servers.dart';
import 'package:scrcpy_connect/stores/usb_lease_recovery.dart';
import 'package:scrcpy_connect/services/app_settings.dart';
import 'package:scrcpy_connect/stores/preference_store.dart';

import 'package:scrcpy_connect/services/application_host_record.dart';

/// 测试替换执行能力，不另造应用原生桥或第二套进程所有者。
class ApplicationHostDependencies {
  const ApplicationHostDependencies();
  bool get desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  UsbLeaseRecovery? usbRecovery() =>
      Platform.isAndroid ? UsbLeaseRecovery() : null;
  Future<NativeAdbApi> bindings() => createNativeScrcpyAdbApi();
  Future<ScrcpyClient> createScrcpy(Uint8List bytes) =>
      createNativeScrcpy(serverBytes: bytes);
  Future<BundledServerFiles> assets(Directory directory) =>
      BundledServers().prepare(directory);
  Future<AdbHost> prepareServer({
    required Directory directory,
    required String identityPath,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) => AdbHost.prepare(
    dataDirectory: directory,
    identityPath: identityPath,
    bindings: bindings,
    admissionScope: admissionScope,
    binaryDirectory: binaryDirectory,
  );
  Future<AdbHost> restoreServer({
    required Directory directory,
    required String leaseId,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) => AdbHost.restore(
    dataDirectory: directory,
    leaseId: leaseId,
    bindings: bindings,
    admissionScope: admissionScope,
    binaryDirectory: binaryDirectory,
  );
}

/// 应用的进程资源组合；同 isolate 的 UI 重新附着复用此所有者。
/// 新 isolate 通过真实原生登记接管，磁盘记录只核验产品策略和所选身份。
final class ApplicationHost {
  ApplicationHost._(
    this.directory,
    this.connectionPolicy,
    this._dependencies,
    this._binaryDirectory,
  );
  static final _active = <String, ApplicationHost>{};
  static final _opening = <String, Future<ApplicationHost>>{};
  static final _retiring = <ApplicationHost>{};
  final Directory directory;
  final ConnectionPolicy connectionPolicy;
  final ApplicationHostDependencies _dependencies;
  final Directory? _binaryDirectory;
  late final NativeAdbApi bindings;
  AdbIdentities get identities => bindings as AdbIdentities;
  late final PreferenceStore preferences;
  late final ScrcpyClient scrcpy;
  late final BundledServerFiles _assets;
  Uint8List get scrcpyBytes => _assets.scrcpyBytes;
  Uint8List get companionBytes => _assets.companionBytes;
  Map<String, Uint8List> get helperArtifacts => _assets.helperArtifacts;
  AdbAdmissionScopeInfo? _scope;
  UsbLeaseRecovery? _usbRecovery;
  bool _usbRecoveryPending = false, _needsRecoveryAttachment = false;
  String? _expectedRecoveryScopeId;
  String? get usbOwnerLeaseId => _usbRecovery?.ownerLeaseId;
  // 接管准入只排空未交付连接；旧代已交付连接仍需业务按精确句柄接管。
  String? _unclaimedConnectionScope;
  final _connectionRecoveries = <String, _ConnectionRecovery>{};

  /// 宿主与应用会话共用同一恢复责任，失败不会在后继连接中另起所有者。
  late final physicalDisplays = PhysicalDisplayRecovery(
    timeout: const Duration(seconds: 15),
  );
  NativeAdbClient? _recoveryClient;
  String? _fileScope;
  String get fileScopeId => _fileScope ?? (throw StateError('文件执行域尚未附着。'));
  late ApplicationHostRecord _record;
  final _clients = <String, AdbClient>{};
  final _servers = <String, AdbHost>{};
  final _pendingRestores = <String, ApplicationIdentityHost>{};
  final _releasingIdentities = <String>{};
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false, _hasBindings = false;
  bool _hasAssets = false, _hasFileHelpers = false, _hasScrcpy = false;
  bool _preparationFailed = false;
  Directory get _records => Directory(p.join(directory.path, 'process_hosts'));
  String get _scopeKey => p.join(directory.path, 'application-host');
  String get _filesKey => p.join(directory.path, 'application-files');
  String get fileScopeKey => _filesKey;

  static Future<ApplicationHost> attach({
    required String dataDirectory,
    ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
    Directory? adbBinaryDirectory,
    ApplicationHostDependencies dependencies =
        const ApplicationHostDependencies(),
  }) async {
    connectionPolicy.validate();
    await closeRetiredHosts();
    final requested = Directory(dataDirectory);
    await requested.create(recursive: true);
    final directory = Directory(await requested.resolveSymbolicLinks());
    final current = _active[directory.path];
    if (current != null) {
      await current._validateAttachment(connectionPolicy, adbBinaryDirectory);
      return current;
    }
    final pending = _opening[directory.path];
    if (pending != null) {
      final host = await pending;
      await host._validateAttachment(connectionPolicy, adbBinaryDirectory);
      return host;
    }
    final host = ApplicationHost._(
      directory,
      connectionPolicy,
      dependencies,
      adbBinaryDirectory,
    );
    final opening = host._initialize();
    _opening[directory.path] = opening;
    try {
      await opening;
      _active[directory.path] = host;
      return host;
    } catch (error, stack) {
      try {
        await host.close();
      } catch (cleanup) {
        _retiring.add(host);
        throw RequestFailure(
          'application_host_cleanup_unconfirmed',
          '宿主初始化失败，部分原生资源尚未确认关闭，可重试清理。',
          {'cause': error.toString(), 'cleanup': cleanup.toString()},
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (identical(_opening[directory.path], opening)) {
        _opening.remove(directory.path);
      }
    }
  }

  /// 初始化失败也不丢弃确切资源；后续 attach 和应用退出可再次排空。
  static Future<void> closeRetiredHosts() async {
    Object? failure;
    for (final host in _retiring.toList()) {
      try {
        await host.close();
        _retiring.remove(host);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  void _check() {
    if (_closed) throw StateError('应用宿主已经停止准入。');
  }

  void _checkPolicy(Map<String, Object?> policy) {
    if (!sameHostPolicy(connectionPolicy.toJson(), policy)) {
      throw const RequestFailure(
        'runtime_connection_policy_mismatch',
        '存活的应用宿主正在使用另一套连接策略，请重启进程。',
      );
    }
  }

  Future<void> _validateAttachment(
    ConnectionPolicy policy,
    Directory? binary,
  ) async {
    _check();
    _checkPolicy(policy.toJson());
    await _checkAuthority();
    if (binary != null &&
        (_binaryDirectory == null ||
            await binary.resolveSymbolicLinks() !=
                await _binaryDirectory.resolveSymbolicLinks())) {
      throw const RequestFailure(
        'host_executable_mismatch',
        '存活宿主的执行文件目录不能改变。',
      );
    }
    await _checkAuthority();
  }

  Future<void> _checkAuthority() async {
    _check();
    final current = await (bindings as NativeAdbAdmissionApi)
        .inspectAdmissionScope(_scopeKey);
    _check();
    if (_scope == null ||
        current?.scopeId != _scope!.scopeId ||
        current?.accepting != true) {
      throw const RequestFailure('application_host_stale', '应用宿主已被后继所有者接管。');
    }
  }

  Future<ApplicationHost> _initialize() async {
    final recordsType = await FileSystemEntity.type(
      _records.path,
      followLinks: false,
    );
    if (recordsType != FileSystemEntityType.directory &&
        recordsType != FileSystemEntityType.notFound) {
      throw const FormatException('宿主恢复目录不是普通目录。');
    }
    bindings = await _dependencies.bindings();
    _hasBindings = true;
    if (bindings is! NativeAdbAdmissionApi ||
        bindings is! NativeAdbScopedFileScopeApi ||
        bindings is! NativeAdbFileApi ||
        bindings is! NativeAdbHandshakeApi ||
        bindings is! AdbIdentities ||
        (_dependencies.desktop && bindings is! NativeAdbScopedServerApi)) {
      throw const RequestFailure(
        'application_host_capability_unavailable',
        '宿主缺少精确恢复和排空所需的执行能力。',
      );
    }
    final admissions = bindings as NativeAdbAdmissionApi;
    final existing = await admissions.inspectAdmissionScope(_scopeKey);
    if (existing != null) {
      _record = await ApplicationHostRecord.read(_records, existing.scopeId);
      if (!sameHostPolicy(_record.policy, connectionPolicy.toJson())) {
        throw const RequestFailure(
          'runtime_connection_policy_mismatch',
          '存活的应用宿主正在使用另一套连接策略，请重启进程。',
        );
      }
    } else {
      _record = ApplicationHostRecord(policy: connectionPolicy.toJson());
    }
    for (final entry in _record.identities.entries) {
      final identity = entry.value;
      if (!p.isAbsolute(identity.identityPath) ||
          _identityKey(identity.identityPath, identity.fingerprint) !=
              entry.key ||
          identity.directory !=
              p.join(_records.path, 'identities', entry.key)) {
        throw const FormatException('宿主身份记录与私有资源目录不一致。');
      }
    }
    _expectedRecoveryScopeId = existing?.scopeId;
    _needsRecoveryAttachment = true;
    _usbRecovery = _dependencies.usbRecovery();
    _usbRecoveryPending = _usbRecovery != null;
    // SDK 换发连接句柄后，旧 disconnect 可能已无对象可关；必须先禁止旧平台释放，
    // 再开始 SDK 接管，不能等到捕获排空之后才给原始 FD 加代次栅栏。
    await _usbRecovery?.begin();
    await _attachRecoveryScope();
    // 全部旧握手先撤销并实际排空，再允许业务打开缓存和任务日志。
    for (final entry in _record.identities.entries.toList()) {
      if (_dependencies.desktop) {
        await _restoreDesktop(entry.key, entry.value);
      } else {
        await _verifyIdentity(entry.value);
      }
    }
    _fileScope = await (bindings as NativeAdbScopedFileScopeApi)
        .fileScopeAttachScoped(_filesKey, _scope!.scopeId);
    await _prepareScrcpy();
    await _recoverConnections(
      scan: _unclaimedConnectionScope != null || _usbRecoveryPending,
    );
    await _completeUsbRecovery();
    preferences = await AppSettings.prepare(directory);
    await _checkAuthority();
    return this;
  }

  Future<void> _attachRecoveryScope() async {
    if (!_needsRecoveryAttachment) return;
    _scope = await (bindings as NativeAdbAdmissionApi).attachAdmissionScope(
      _scopeKey,
      expectedScopeId: _expectedRecoveryScopeId,
    );
    _unclaimedConnectionScope = _expectedRecoveryScopeId;
    _needsRecoveryAttachment = false;
    // 初始化回滚也可能首次取得 scope；此时应用已经撤销准入，但仍须保存实际恢复事实。
    // 仅此接管路径允许已关闭宿主写入，并在前后核验精确原生权限。
    await _requireRecoveryAuthority();
    await _record.write(_records, _scope!.scopeId);
    await _requireRecoveryAuthority();
  }

  Future<void> _completeUsbRecovery() async {
    if (!_usbRecoveryPending) return;
    await _requireRecoveryAuthority();
    await _usbRecovery!.complete();
    _usbRecoveryPending = false;
  }

  Future<void> _finishUsbRecoveryForClose() async {
    // 开始或完成的回复丢失也保留同一候选。初始化失败不能绕过 SDK 排空直接关 FD，
    // 必要时先完成原 scope 接管，再认领并释放所有属于本命名域的旧连接。
    await _usbRecovery!.begin();
    await _attachRecoveryScope();
    await _recoverConnections(scan: true);
    await _completeUsbRecovery();
  }

  Future<void> _prepareScrcpy() async {
    // 初始化失败后的 close 也可重试取得同库捕获排空能力，不另建连接。
    if (!_hasAssets) {
      _assets = await _dependencies.assets(directory);
      _hasAssets = true;
    }
    if (!_hasFileHelpers) {
      await (bindings as NativeAdbFileApi).initializeFileHelpers([
        for (final entry in _assets.helperArtifacts.entries)
          AdbFileHelper(entry.key, entry.value),
      ]);
      _hasFileHelpers = true;
    }
    if (!_hasScrcpy) {
      scrcpy = await _dependencies.createScrcpy(_assets.scrcpyBytes);
      _hasScrcpy = true;
    }
  }

  /// 排空上次 isolate 已交付的连接；成功之前不把旧代标记当成冷启动。
  Future<void> recoverConnections() => _queueConnectionRecovery(false);

  /// 身份管理器尚未建立设备所有者时使用，先于修改身份或建立新连接执行。
  /// 只处理本宿主命名域及已认领服务器的真实连接，不关闭其他应用域。
  Future<void> drainConnections() => _queueConnectionRecovery(true);

  Future<void> _queueConnectionRecovery(bool drainCurrent) {
    _check();
    final operation = _tail.then((_) async {
      await _checkAuthority();
      await _recoverConnections(
        scan: drainCurrent || _unclaimedConnectionScope != null,
      );
      await _checkAuthority();
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _requireRecoveryAuthority() async {
    final current = await (bindings as NativeAdbAdmissionApi)
        .inspectAdmissionScope(_scopeKey);
    if (_scope == null ||
        current?.scopeId != _scope!.scopeId ||
        current?.accepting != true) {
      throw const RequestFailure('application_host_stale', '应用宿主已被后继所有者接管。');
    }
  }

  Future<void> _recoverConnections({required bool scan}) async {
    await _requireRecoveryAuthority();
    final ownedServers = {
      for (final owner in _servers.values)
        if (owner.nativeConfiguration?['serverId'] case final String id) id,
    };
    if (scan) {
      // 只凭已确认 scoped 交付事实筛选；相同 serial、端点或公钥均不继承归属。
      for (final device in await bindings.devices()) {
        if (_connectionRecoveries.values.any(
          (entry) => entry.device.id == device.id,
        )) {
          continue;
        }
        final facts = await bindings.connectionFacts(device.id);
        if (facts.admissionScopeKey != _scopeKey) continue;
        if (_dependencies.desktop && !ownedServers.contains(facts.serverId)) {
          continue;
        }
        _connectionRecoveries.putIfAbsent(
          device.id,
          () => _ConnectionRecovery(
            AdbDevice(
              id: device.id,
              serial: device.serial,
              state: device.state,
              features: device.features,
              nativeOwner: bindings,
            ),
          ),
        );
      }
      // 列举期间可能已换代，后续 scoped claim 还会在原生锁内再次核验。
      await _requireRecoveryAuthority();
    }
    await _drainConnectionRecoveries();
    if (_pendingRestores.isEmpty) _unclaimedConnectionScope = null;
  }

  Future<void> _drainConnectionRecoveries() async {
    Object? failure;
    StackTrace? stack;
    for (final entry in _connectionRecoveries.entries.toList()) {
      try {
        await _drainConnectionRecovery(entry.value);
        _connectionRecoveries.remove(entry.key);
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  Future<void> _drainConnectionRecovery(_ConnectionRecovery recovery) async {
    final admissions = bindings as NativeAdbAdmissionApi;
    final handshakes = bindings as NativeAdbHandshakeApi;
    if (!recovery.claimed) {
      // 前次 claim 失败也须先结清它的单次握手；不能覆盖未确认登记。
      if (recovery.handshake case final handshake?) {
        await handshakes.closeHandshake(handshake);
        recovery.handshake = null;
      }
      await _requireRecoveryAuthority();
      final facts = await bindings.connectionFacts(recovery.device.id);
      if (facts.admissionScopeKey != _scopeKey) {
        throw const RequestFailure(
          'application_host_connection_mismatch',
          '待恢复连接不属于本宿主准入域，保留责任但不操作其他所有者。',
        );
      }
      // 已关闭连接不能认领；仍按原精确句柄回收残余捕获和本机 driver。
      if (facts.closed) {
        recovery.claimed = true;
        recovery.closedBeforeClaim = true;
      } else {
        recovery.handshake = await admissions.createScopedHandshake(
          _scope!.scopeId,
        );
        final device = await admissions.claimScopedConnection(
          recovery.device.id,
          recovery.handshake!,
        );
        recovery.device = AdbDevice(
          id: device.id,
          serial: device.serial,
          state: device.state,
          features: device.features,
          nativeOwner: bindings,
        );
        // 先保存新句柄再确认交付；确认失败仍由原对象保存精确清理责任。
        recovery.claimed = true;
        await admissions.confirmHandshakeConnection(
          recovery.handshake!,
          device.id,
        );
      }
    }
    if (!recovery.capturesDrained) {
      await _prepareScrcpy();
      await scrcpy.drainConnection(recovery.device);
      recovery.capturesDrained = true;
    }
    if (!recovery.displaySettled) {
      if (!recovery.closedBeforeClaim) {
        // 服务器接管不排空已交付连接；先认领撤旧 raw，再排空捕获，最后核验显示。
        // OfficialAdbClient 不认识认领的原生句柄，恢复只借同库客户端执行已有连接。
        final client = _recoveryClient ??= NativeAdbClient(
          bindings,
          '',
          admissionScope: _scope,
          ownsAdmissionScope: false,
        );
        final connection = recovery.connection ??= DeviceConnection(
          client: client,
          device: recovery.device,
        );
        if ((await bindings.connectionFacts(recovery.device.id)).closed) {
          await physicalDisplays.detachClosedConnection(connection);
        } else {
          try {
            await physicalDisplays.recover(connection);
            await physicalDisplays.stopForConnection(connection);
          } catch (_) {
            // 只有同一句柄的原生 closed 事实允许延期远端恢复；未知状态仍保留通道。
            if (!(await bindings.connectionFacts(recovery.device.id)).closed) {
              rethrow;
            }
            await physicalDisplays.detachClosedConnection(connection);
          }
        }
      }
      // 已关闭的传输无法提供远端证明；下一条连接在准入阶段必须恢复 current。
      recovery.displaySettled = true;
    }
    if (!recovery.disconnected) {
      await bindings.disconnect(recovery.device.id);
      recovery.disconnected = true;
    }
    if (recovery.handshake case final handshake?) {
      await handshakes.closeHandshake(handshake);
      recovery.handshake = null;
    }
  }

  Future<void> _save() async {
    await _checkAuthority();
    await _record.write(_records, _scope!.scopeId);
    await _checkAuthority();
  }

  String _identityKey(String path, String fingerprint) =>
      sha256.convert(utf8.encode('$path\u0000$fingerprint')).toString();
  Future<String> _identityPath(String identityPath) async {
    final file = File(identityPath).absolute;
    return p.join(
      await file.parent.resolveSymbolicLinks(),
      p.basename(file.path),
    );
  }

  Future<void> _verifyIdentity(ApplicationIdentityHost identity) async {
    final actual = await identities.inspectIdentity(identity.identityPath);
    if (actual == null || actual.fingerprint != identity.fingerprint) {
      throw const RequestFailure(
        'host_identity_mismatch',
        '存活宿主的授权身份已改变，不能替换或复用原服务器。',
      );
    }
  }

  Future<void> _restoreDesktop(
    String key,
    ApplicationIdentityHost identity,
  ) async {
    final owner = await _claimDesktop(key, identity);
    if (owner == null) return;
    // 先保留精确关闭权，再验证磁盘身份；失败绝不交付产品执行能力。
    await _verifyIdentity(identity);
    _clients[key] = owner.client;
    await _save();
  }

  Future<AdbHost?> _claimDesktop(
    String key,
    ApplicationIdentityHost identity,
  ) async {
    // 查询失败也不能把未知资源当成不存在；仅明确的首次未登记结果可撤销此责任。
    _pendingRestores[key] = identity;
    final servers = await (bindings as NativeAdbServerApi).listServers();
    final prefix = p.join(identity.directory, 'official_adb');
    final matches = servers.where((server) {
      if (identity.serverId != null) {
        return server.serverId == identity.serverId;
      }
      final home = server.launch.environment['ANDROID_USER_HOME'];
      return home != null &&
          p.isWithin(prefix, home) &&
          server.launch.environment['ADB_VENDOR_KEYS'] == identity.identityPath;
    }).toList();
    if (matches.isEmpty && identity.serverId == null) {
      _pendingRestores.remove(key);
      return null;
    }
    if (matches.length != 1) {
      throw const RequestFailure(
        'host_resource_missing',
        '原服务器登记缺失或不唯一，不能启动替代服务器。',
      );
    }
    final server = matches.single;
    final home = server.launch.environment['ANDROID_USER_HOME'];
    if (server.launch.environment['ADB_VENDOR_KEYS'] != identity.identityPath ||
        home == null ||
        !p.isWithin(prefix, home)) {
      throw const RequestFailure('host_identity_mismatch', '原服务器与已登记身份或目录不一致。');
    }
    // SDK 在 claim 前失败时，保留原全局标记和确定的待恢复对象供 close 重试。
    _pendingRestores[key] = identity;
    final owner = await _dependencies.restoreServer(
      directory: Directory(identity.directory),
      leaseId: server.leaseId,
      bindings: bindings,
      admissionScope: _scope!,
      binaryDirectory: _binaryDirectory,
    );
    _servers[key] = owner;
    _pendingRestores.remove(key);
    _record.identities[key] = identity.withServer(server.serverId);
    return owner;
  }

  /// 身份由应用选择，本模块核对公开事实并组装同库执行能力。
  Future<AdbClient> clientForIdentity({
    required String identityPath,
    required String fingerprint,
  }) {
    _check();
    final operation = _tail.then((_) async {
      await _checkAuthority();
      await _recoverConnections(scan: _unclaimedConnectionScope != null);
      if (_preparationFailed) {
        throw const RequestFailure(
          'application_host_cleanup_unconfirmed',
          '上次宿主创建尚未确认清理，不能启动替代服务器。',
        );
      }
      final path = await _identityPath(identityPath);
      final key = _identityKey(path, fingerprint);
      if (_releasingIdentities.contains(key)) {
        throw const RequestFailure(
          'application_host_cleanup_unconfirmed',
          '此身份客户端正在回收，须先重试确认关闭。',
        );
      }
      final identity =
          _record.identities[key] ??
          ApplicationIdentityHost(
            identityPath: path,
            fingerprint: fingerprint,
            directory: p.join(_records.path, 'identities', key),
          );
      await _verifyIdentity(identity);
      await _checkAuthority();
      if (_clients[key] case final client?) return client;
      _record.identities[key] = identity;
      await _save();
      if (_dependencies.desktop) {
        await _restoreDesktop(key, identity);
        if (_clients[key] case final client?) return client;
        await Directory(identity.directory).create(recursive: true);
        final AdbHost owner;
        try {
          owner = await _dependencies.prepareServer(
            directory: Directory(identity.directory),
            identityPath: path,
            bindings: bindings,
            admissionScope: _scope!,
            binaryDirectory: _binaryDirectory,
          );
        } catch (_) {
          // 原生 scope 保留未交付 reservation 的回收权，禁止另起服务器掩盖失败。
          _preparationFailed = true;
          rethrow;
        }
        _servers[key] = owner;
        _clients[key] = owner.client;
        final id = owner.nativeConfiguration?['serverId'];
        if (id is! String) throw StateError('受控宿主未返回服务器身份。');
        _record.identities[key] = identity.withServer(id);
      } else {
        _clients[key] = NativeAdbClient(
          bindings,
          path,
          admissionScope: _scope,
          ownsAdmissionScope: false,
        );
      }
      await _save();
      await _checkAuthority();
      return _clients[key]!;
    });
    final result = operation;
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// 回收临时候选身份的精确客户端，再允许调用方删除候选 PEM。
  /// 调用方必须先排空该客户端的连接；不得用于仍有活动连接的身份。
  /// 关闭或记录提交失败时保留原对象，重试此方法不会另建服务器。
  Future<void> releaseIdentityClient({
    required String identityPath,
    required String fingerprint,
  }) {
    _check();
    final operation = _tail.then((_) async {
      await _checkAuthority();
      final path = await _identityPath(identityPath);
      final key = _identityKey(path, fingerprint);
      final identity = _record.identities[key];
      if (identity == null &&
          !_clients.containsKey(key) &&
          !_servers.containsKey(key) &&
          !_pendingRestores.containsKey(key)) {
        return;
      }
      _releasingIdentities.add(key);
      if (_pendingRestores[key] case final pending?) {
        await _claimDesktop(key, pending);
      }
      if (_servers[key] case final owner?) {
        await owner.close();
      } else if (_clients[key] case final client?) {
        await client.close();
      } else if (_preparationFailed) {
        // 尚未交付的原生 reservation 仍归整个准入域回收，不能删掉恢复事实。
        throw const RequestFailure(
          'application_host_cleanup_unconfirmed',
          '身份宿主创建尚未确认清理，请先重试关闭应用宿主。',
        );
      }
      // 即使对象已关闭，也保留登记直至持久提交确认，防止再次交付它。
      _record.identities.remove(key);
      try {
        await _save();
      } catch (_) {
        if (identity != null) _record.identities[key] = identity;
        rethrow;
      }
      _servers.remove(key);
      _clients.remove(key);
      _pendingRestores.remove(key);
      _releasingIdentities.remove(key);
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    Object? failure;
    StackTrace? failureStack;
    Future<void> release(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    try {
      await _tail;
      if (_hasBindings) {
        // 先取得服务器关闭权，才能按其真实身份筛出旧连接；直接关服务器会丢掉恢复通道。
        for (final entry in _pendingRestores.entries.toList()) {
          await release(() async {
            final current = await (bindings as NativeAdbAdmissionApi)
                .inspectAdmissionScope(_scopeKey);
            if (current?.scopeId != _scope?.scopeId) {
              _pendingRestores.remove(entry.key);
              return;
            }
            await _claimDesktop(entry.key, entry.value);
          });
        }
        if (_usbRecoveryPending) {
          await release(_finishUsbRecoveryForClose);
        } else if (_unclaimedConnectionScope != null ||
            _connectionRecoveries.isNotEmpty) {
          await release(() async {
            final current = await (bindings as NativeAdbAdmissionApi)
                .inspectAdmissionScope(_scopeKey);
            if (_scope != null && current?.scopeId == _scope!.scopeId) {
              await _recoverConnections(
                scan: _unclaimedConnectionScope != null,
              );
            } else {
              if (current == null) {
                throw const RequestFailure(
                  'application_host_recovery_unconfirmed',
                  '宿主标记缺失不能证明旧连接已回收，仍保留精确责任供重试。',
                );
              }
              // 后继 scope 已排空旧握手；旧宿主只可清理已经取得的精确连接。
              _connectionRecoveries.removeWhere(
                (_, recovery) => !recovery.claimed,
              );
              await _drainConnectionRecoveries();
              _unclaimedConnectionScope = null;
            }
          });
        }
        if (failure == null) await release(physicalDisplays.close);
        if (_fileScope case final id?) {
          await release(() async {
            await (bindings as NativeAdbFileScopeApi).fileScopeClose(id);
            _fileScope = null;
          });
        }
        if (failure == null) {
          // 捕获、显示或文件仍未结清时，保留它们依赖的客户端和服务器供原对象重试。
          for (final entry in _servers.entries.toList()) {
            await release(() async {
              await entry.value.close();
              _servers.remove(entry.key);
              _clients.remove(entry.key);
            });
          }
          for (final entry in _clients.entries.toList()) {
            if (_servers.containsKey(entry.key)) continue;
            await release(() async {
              await entry.value.close();
              _clients.remove(entry.key);
            });
          }
          await release(() async {
            await _recoveryClient?.close();
            _recoveryClient = null;
          });
        }
        // 未确认资源保留全局标记，不能让冷启动误认没有存活进程。
        if (failure == null) {
          if (_scope case final scope?) {
            await release(() async {
              await (bindings as NativeAdbAdmissionApi).closeAdmissionScope(
                scope.scopeId,
              );
              _scope = null;
            });
          }
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
      if (identical(_active[directory.path], this)) {
        _active.remove(directory.path);
      }
      _retiring.remove(this);
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// 接管失败保留原对象，已取得的新句柄不会被下一次扫描或重试覆盖。
final class _ConnectionRecovery {
  _ConnectionRecovery(this.device);
  AdbDevice device;
  String? handshake;
  DeviceConnection? connection;
  bool claimed = false, capturesDrained = false, disconnected = false;
  bool closedBeforeClaim = false, displaySettled = false;
}
