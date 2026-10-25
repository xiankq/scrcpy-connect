import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/services/connection/device_query.dart';
import 'package:scrcpy_connect/stores/connection/identity_manager.dart';
import 'package:scrcpy_connect/models/device_record.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';

enum DeviceObservationStatus { unknown, ok, error }

/// 一组实际查询事实；未知、执行失败与不支持由解释层分别处理。
final class DeviceCapabilityObservation {
  const DeviceCapabilityObservation.unknown()
    : status = DeviceObservationStatus.unknown,
      text = null,
      code = null,
      message = null;
  const DeviceCapabilityObservation.ok([this.text])
    : status = DeviceObservationStatus.ok,
      code = null,
      message = null;
  const DeviceCapabilityObservation.error(this.code, this.message)
    : status = DeviceObservationStatus.error,
      text = null;

  final DeviceObservationStatus status;
  final String? text, code, message;
  bool get succeeded => status == DeviceObservationStatus.ok;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'stdout': ?text,
    'code': ?code,
    'message': ?message,
  };
}

/// 单次查询绑定的连接事实；快照回调只读取已有所有者，不部署或恢复活动。
final class DeviceCapabilityFacts {
  DeviceCapabilityFacts({
    required this.record,
    required this.connected,
    required this.connectionId,
    required List<String> features,
    required Map<String, DeviceCapabilityObservation> observations,
    required this.identity,
    required Map<String, Object?> companion,
    required this.streaming,
    required this.audioPlaying,
    required this.usbBackendAvailable,
    required this.assertCurrent,
  }) : features = List.unmodifiable(features),
       observations = Map.unmodifiable(observations),
       companion = Map.unmodifiable(companion);

  final DeviceRecord record;
  final bool connected, streaming, audioPlaying;
  final String? connectionId;
  final bool? usbBackendAvailable;
  final List<String> features;
  final Map<String, DeviceCapabilityObservation> observations;
  final DeviceCapabilityObservation identity;
  final Map<String, Object?> companion;

  /// 解释层等待本机媒体信息之后仍须复核原连接、端点和授权身份。
  final Future<void> Function() assertCurrent;

  DeviceCapabilityObservation observation(String group) =>
      observations[group] ?? const DeviceCapabilityObservation.unknown();

  Map<String, Object?> toJson() => {
    'deviceId': record.id,
    'device': {
      ...record.toJson(),
      'status': connected
          ? 'connected'
          : record.status == 'unauthorized'
          ? 'unauthorized'
          : 'offline',
      'connectionId': connectionId,
    },
    'connected': connected,
    'connectionId': connectionId,
    'features': features,
    'identity': identity.toJson(),
    'observations': {
      for (final entry in observations.entries) entry.key: entry.value.toJson(),
    },
    'usbBackendAvailable': usbBackendAvailable,
  };
}

/// 从应用的精确连接和公开 SDK 读取有界事实，不承担连接、部署或记录写入。
final class DeviceCapabilityFactsReader {
  DeviceCapabilityFactsReader({
    required this.records,
    required this.identities,
    required this.connectionForDevice,
    required this.policy,
    this.companionState,
    this.sessions,
    this.audioSources,
    Future<Socket> Function(String, int, Duration)? openTcp,
  }) : _openTcp =
           openTcp ??
           ((host, port, timeout) =>
               Socket.connect(host, port, timeout: timeout));

  final DeviceRecordStore records;
  final IdentityManager identities;
  final DeviceConnection? Function(String) connectionForDevice;
  final ConnectionPolicy policy;
  final Map<String, Object?> Function(String)? companionState;
  final List<Map<String, Object?>> Function()? sessions, audioSources;
  final Future<Socket> Function(String, int, Duration) _openTcp;

  static const shellCommand = "printf 'interop-capability-check'";
  static const packagesCommand = 'pm list packages';
  static const wirelessCommand = r'''for property in service.adb.tcp.port persist.adb.tcp.port persist.adb.tls_server.enable service.adb.tls.port; do
printf '%s=' "$property"
getprop "$property" || exit
done''';

  Future<DeviceCapabilityFacts> read(
    String deviceId, {
    required bool diagnose,
    AdbCancellation? cancellation,
  }) async {
    if (!validDeviceId(deviceId)) {
      throw const ApplicationCommandException('invalid_device_id', '设备记录标识无效。');
    }
    final record = records.current.find(deviceId);
    if (record == null) {
      throw const ApplicationCommandException('device_not_found', '设备记录已不存在。');
    }
    final connection = connectionForDevice(deviceId);
    final fingerprint =
        records.current.deviceIdentityFingerprints[deviceId] ??
        records.current.identityFingerprint;
    void guard() {
      cancellation?.check();
      final latest = records.current.find(deviceId);
      if (!identical(connectionForDevice(deviceId), connection) ||
          latest == null ||
          latest.address != record.address ||
          latest.port != record.port ||
          latest.transport != record.transport ||
          latest.guid != record.guid ||
          (records.current.deviceIdentityFingerprints[deviceId] ??
                  records.current.identityFingerprint) !=
              fingerprint) {
        throw const ApplicationCommandException(
          'stale_connection',
          '检查期间设备连接、地址或授权身份已改变，请重新检查。',
        );
      }
    }

    Future<DeviceCapabilityObservation> observe(
      Future<DeviceCapabilityObservation> Function() query,
    ) async {
      guard();
      try {
        return await query();
      } catch (error, stack) {
        final (code, message) = switch (error) {
          AdbException(:final code, :final message) => (code, message),
          ApplicationCommandException(:final code, :final message) => (
            code,
            message,
          ),
          _ => Error.throwWithStackTrace(error, stack),
        };
        if (const {
          'cancelled',
          'stale_connection',
          'disposed',
        }.contains(code)) {
          rethrow;
        }
        return DeviceCapabilityObservation.error(code, message);
      } finally {
        // 失败同样可能迟到，不能将旧连接的错误拼进后继连接诊断。
        guard();
      }
    }

    IdentitySelection? selected;
    final identity = await observe(() async {
      // 只 inspect 已绑定的材料，不 prepare、不迁移，也不新建客户端。
      selected = await identities.selectForDevice(deviceId);
      return const DeviceCapabilityObservation.ok();
    });
    Future<void> assertCurrent() async {
      guard();
      if (selected case final value?) {
        await identities.validateSelection(value, deviceId: deviceId);
      }
      guard();
    }

    final observations = <String, DeviceCapabilityObservation>{};
    String? connectionId;
    List<String> features = const [];
    Future<void> readConnection() async {
      if (connection == null) return;
      observations['connection'] = await observe(() async {
        final facts = await connection.client.services.connectionFacts(
          connection.device,
        );
        if (facts.closed ||
            connectionId != null && facts.connectionId != connectionId) {
          throw const ApplicationCommandException(
            'stale_connection',
            '实际设备连接已关闭或替换。',
          );
        }
        if (facts.connectionId == null || facts.connectionId!.isEmpty) {
          throw const ApplicationCommandException(
            'query_unavailable',
            '当前连接的技术身份尚未取得。',
          );
        }
        connectionId = facts.connectionId;
        features = facts.features;
        return const DeviceCapabilityObservation.ok();
      });
    }

    await readConnection();
    if (diagnose) {
      observations['tcp'] =
          record.transport == DeviceTransport.usb ||
              record.address.isEmpty ||
              record.port == 0
          ? const DeviceCapabilityObservation.unknown()
          : await observe(() => _tcp(record));
    }
    if (connection != null) {
      Future<DeviceCapabilityObservation> text(String command, int limit) =>
          observe(
            () async => DeviceCapabilityObservation.ok(
              await readDeviceText(
                connection,
                command,
                cancellation: cancellation,
                timeout: policy.probeTimeout,
                maxBytes: limit,
              ),
            ),
          );
      if (diagnose) {
        observations['wirelessProperties'] = await text(wirelessCommand, 4096);
      } else {
        observations['shell'] = await text(shellCommand, 4096);
        observations['sync'] = await observe(() async {
          await connection.client.services
              .sync(connection.device)
              .stat(
                AdbPath('/sdcard'),
                timeout: policy.probeTimeout,
                cancellation: cancellation,
              );
          return const DeviceCapabilityObservation.ok();
        });
        observations['packages'] = await text(packagesCommand, 256 * 1024);
      }
    }
    await readConnection();
    await assertCurrent();
    final companion = connection == null
        ? const <String, Object?>{}
        : companionState?.call(deviceId) ?? const <String, Object?>{};
    final streaming =
        connection != null &&
        (sessions?.call() ?? const <Map<String, Object?>>[]).any(
          (item) =>
              item['deviceId'] == deviceId && item['status'] == 'streaming',
        );
    final audioPlaying =
        connection != null &&
        (audioSources?.call() ?? const <Map<String, Object?>>[]).any(
          (item) =>
              item['deviceId'] == deviceId &&
              item['status'] == 'playing' &&
              item['nativeAttached'] == true,
        );
    guard();
    return DeviceCapabilityFacts(
      record: record,
      connected: connection != null,
      connectionId: connectionId,
      features: features,
      observations: observations,
      identity: identity,
      companion: companion,
      streaming: streaming,
      audioPlaying: audioPlaying,
      usbBackendAvailable: connection == null
          ? null
          : connection.client.capabilities.officialServer ||
                connection.client.capabilities.androidUsbFd,
      assertCurrent: assertCurrent,
    );
  }

  Future<DeviceCapabilityObservation> _tcp(DeviceRecord record) async {
    Socket? socket;
    try {
      socket = await _openTcp(record.address, record.port, policy.probeTimeout);
      return const DeviceCapabilityObservation.ok();
    } on SocketException catch (error) {
      final code = switch (error.osError?.errorCode) {
        1 || 13 || 10013 => 'permission_denied',
        61 || 111 || 10061 => 'connection_refused',
        _ => 'network_error',
      };
      return DeviceCapabilityObservation.error(code, error.message);
    } on TimeoutException {
      return const DeviceCapabilityObservation.error(
        'connect_timeout',
        'TCP 连接超时。',
      );
    } finally {
      // 普通 TCP 探测不发送 ADB/TLS 内容，不借此声称对端已授权。
      socket?.destroy();
    }
  }
}
