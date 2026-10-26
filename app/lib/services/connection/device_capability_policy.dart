import 'package:scrcpy_connect/models/application_request.dart' show Json;
import 'package:scrcpy_connect/models/application_command_exception.dart';

import 'package:scrcpy_connect/services/connection/device_capability_facts_reader.dart';

/// 根据明确的执行事实组装产品功能说明，不分派底层 JSON 探测命令。
class DeviceCapabilityPolicy {
  DeviceCapabilityPolicy({
    required this.facts,
    required this.burstRequested,
    this.localVideoCapabilities,
  });

  final DeviceCapabilityFactsReader facts;
  final bool Function() burstRequested;
  final Future<Json> Function()? localVideoCapabilities;

  bool handles(String command) =>
      command == 'device.capabilities' || command == 'device.diagnose';

  Future<Json> request(String command, Json params) async {
    if (!handles(command)) {
      throw const ApplicationCommandException('unknown_command', '未知设备解释请求。');
    }
    final id = params['deviceId'];
    if (id is! String) {
      throw const ApplicationCommandException('invalid_device_id', '设备记录标识无效。');
    }
    final diagnosis = command == 'device.diagnose';
    final observed = await facts.read(id, diagnose: diagnosis);
    if (diagnosis) {
      final tcp = observed.observation('tcp');
      final identity = observed.identity;
      await observed.assertCurrent();
      return {
        ...observed.toJson(),
        'tcpReachable': tcp.succeeded
            ? true
            : tcp.status == DeviceObservationStatus.error &&
                  tcp.code != 'permission_denied'
            ? false
            : null,
        'networkError': tcp.code,
        'identityPresent': identity.succeeded
            ? true
            : identity.code == 'identity_unavailable'
            ? false
            : null,
        'identityError': identity.code,
        'adbBurstRequested': burstRequested(),
        'wirelessProperties': observed.observation('wirelessProperties').text,
        'notes': [
          if (tcp.code == 'permission_denied') '主控网络权限未允许，请先检查系统权限；手填地址不能绕过权限。',
          if (observed.record.transport.name == 'tls') '配对端口与连接端口不同。',
          'mDNS 不可用时仍可手动填写可达的连接地址。',
          '网络可达、已配对与设备连接是独立状态。',
        ],
      };
    }
    final api = observed.record.apiLevel;
    final connected = observed.connected;
    final companion = observed.companion;
    final entries = <Json>[];
    void add(String id, String status, String reason) => entries.add({
      'id': id,
      'key': id,
      'name': id,
      'status': status,
      'reason': reason,
    });
    final shell = observed.observation('shell');
    add(
      'shell',
      !connected
          ? 'unknown'
          : shell.succeeded && shell.text == 'interop-capability-check'
          ? 'available'
          : 'limited',
      !connected
          ? '设备尚未连接，无法探测。'
          : shell.succeeded && shell.text == 'interop-capability-check'
          ? '已通过当前设备授权连接验证 shell。'
          : 'ADB 已连接，但 shell 探测未成功。',
    );
    add(
      'files',
      !connected
          ? 'unknown'
          : observed.observation('sync').succeeded
          ? 'available'
          : 'limited',
      !connected
          ? '设备尚未连接，无法探测。'
          : observed.observation('sync').succeeded
          ? '已通过当前连接验证文件服务；受 Android 文件权限限制。'
          : '当前文件服务探测失败，可查看连接诊断。',
    );
    add(
      'wirelessPairing',
      api != null && api < 30
          ? 'unavailable'
          : observed.record.guid != null
          ? 'available'
          : api == null
          ? 'unknown'
          : 'needsSetup',
      api != null && api < 30
          ? '设备 Android 版本低于 11，可使用授权 USB 开启 IP 连接。'
          : observed.record.guid != null
          ? '已配对；当前连接状态单独判断。'
          : api == null
          ? '尚未读取 Android 版本，无线配对能力待确认。'
          : '请在被控设备开启无线调试并完成配对。',
    );
    final streaming = observed.streaming;
    final video = localVideoCapabilities == null
        ? <String, dynamic>{}
        : await localVideoCapabilities!();
    add(
      'screen',
      api != null && api < 21
          ? 'unavailable'
          : !connected || api == null
          ? 'unknown'
          : streaming
          ? 'available'
          : 'limited',
      api != null && api < 21
          ? '整机远控需要 Android 5.0 或更新版本。'
          : !connected || api == null
          ? '设备未连接或 Android 版本尚未读取。'
          : streaming
          ? '当前设备已有实际视频控制会话。'
          : video['available'] == false
          ? '本机视频呈现尚不可用。'
          : '编码器及厂商输入权限在实际启动时确认。',
    );
    add(
      'clipboard',
      api != null && api < 21
          ? 'unavailable'
          : !connected
          ? 'unknown'
          : streaming
          ? 'limited'
          : 'unknown',
      api != null && api < 21
          ? '互联文本通道需要 Android 5.0 或更新版本。'
          : 'scrcpy 文本通道按获焦画面、实际读回与本机前台权限判断。',
    );
    final packages = observed.observation('packages');
    final packageReadable =
        packages.succeeded && (packages.text?.startsWith('package:') ?? false);
    add(
      'apps',
      !connected
          ? 'unknown'
          : packageReadable && api != null && api >= 29
          ? 'available'
          : 'limited',
      !connected
          ? '设备尚未连接，无法探测应用能力。'
          : packageReadable
          ? '已读取设备包列表；独立应用窗口要求 Android 10+，具体启动仍按系统与应用条件判断。'
          : '应用列表探测未成功，不能据此认定不支持。',
    );
    final playing = observed.audioPlaying;
    add(
      'audio',
      playing
          ? 'available'
          : api != null && api < 30
          ? 'unavailable'
          : 'unknown',
      playing
          ? '该设备当前已有实际主控播放器；捕获仍受应用内容权限约束。'
          : api != null && api < 30
          ? '声音转发要求 Android 11或更新版本。'
          : '尚无实际播放结果，请在声音页主动开启后确认。',
    );
    for (final key in ['notifications', 'calls']) {
      final feature = _object(companion[key]);
      add(
        key,
        feature['controlStatus'] as String? ??
            feature['status'] as String? ??
            'unknown',
        feature['reason'] as String? ?? '当前没有可核验的实时状态，请在对应功能页检查。',
      );
    }
    add('background', 'unknown', '后台保持由主控系统权限、电量策略与当前活动决定。');
    // 宿主能力查询可能异步等待，应丢弃被替换设备的事实。
    await observed.assertCurrent();
    return {
      'deviceId': params['deviceId'],
      'connectionId': observed.connectionId,
      'capabilities': entries,
      'features': observed.features,
    };
  }
}

Json _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
