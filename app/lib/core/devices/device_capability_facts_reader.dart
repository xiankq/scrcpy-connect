import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_capability_facts.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_query.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_capability_observation.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';

/// 从应用的精确连接和公开 SDK 读取有界事实，不承担连接、部署或记录写入。
final class DeviceCapabilityFactsReader {
  DeviceCapabilityFactsReader({
    required this.records,
    required this.identities,
    required this.connectionForDevice,
    required this.policy,
    this.observationCapabilities,
    this.sessions,
    this.audioSources,
    Future<Socket> Function(String, int, Duration)? openTcp,
  }) : _openTcp =
           openTcp ??
           ((host, port, timeout) =>
               Socket.connect(host, port, timeout: timeout));

  final DeviceRecordStorage records;
  final AdbIdentityService identities;
  final DeviceConnection? Function(String) connectionForDevice;
  final ConnectionPolicy policy;
  final List<DeviceCapability> Function(String)? observationCapabilities;
  final List<VideoSessionSnapshot> Function()? sessions;
  final List<DeviceAudioSnapshot> Function()? audioSources;
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
      throw const RequestFailure('invalid_device_id', '设备记录标识无效。');
    }
    final record = records.current.find(deviceId);
    if (record == null) {
      throw const RequestFailure('device_not_found', '设备记录已不存在。');
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
        throw const RequestFailure(
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
          RequestFailure(:final code, :final message) => (code, message),
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
          throw const RequestFailure('stale_connection', '实际设备连接已关闭或替换。');
        }
        if (facts.connectionId == null || facts.connectionId!.isEmpty) {
          throw const RequestFailure('query_unavailable', '当前连接的技术身份尚未取得。');
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
    final observedCapabilities = connection == null
        ? const <DeviceCapability>[]
        : observationCapabilities?.call(deviceId) ?? const <DeviceCapability>[];
    final streaming =
        connection != null &&
        (sessions?.call() ?? const <VideoSessionSnapshot>[]).any(
          (item) =>
              item.deviceId == deviceId &&
              item.status == VideoSessionStatus.streaming,
        );
    final audioPlaying =
        connection != null &&
        (audioSources?.call() ?? const <DeviceAudioSnapshot>[]).any(
          (item) =>
              item.deviceId == deviceId &&
              item.status == DeviceAudioStatus.playing &&
              item.nativeAttached,
        );
    guard();
    return DeviceCapabilityFacts(
      record: record,
      connected: connection != null,
      connectionId: connectionId,
      features: features,
      observations: observations,
      identity: identity,
      observationCapabilities: observedCapabilities,
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
