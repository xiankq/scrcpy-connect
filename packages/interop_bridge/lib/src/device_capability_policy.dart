// Public constructor dependency names remain independent of private storage.
// ignore_for_file: prefer_initializing_formals
import 'connection_policy.dart';
import 'connection_setup_coordinator.dart' show SetupJson, SetupRequest;
import 'interop_exception.dart';

/// Product feature explanations assembled from explicit native observations.
class DeviceCapabilityPolicy {
  DeviceCapabilityPolicy({
    required SetupRequest request,
    required this.policy,
    this.localVideoCapabilities,
  }) : _request = request;

  final SetupRequest _request;
  final ConnectionPolicy policy;
  final Future<SetupJson> Function()? localVideoCapabilities;

  bool handles(String command) =>
      command == 'device.capabilities' || command == 'device.diagnose';

  Future<SetupJson> request(String command, SetupJson params) async {
    final diagnosis = command == 'device.diagnose';
    final facts = await _request('adb.device.probe', {
      'deviceId': params['deviceId'],
      'probes': diagnosis
          ? ['tcp', 'wirelessProperties']
          : ['shell', 'sync', 'packages'],
      'timeoutMs': policy.probeTimeout.inMilliseconds,
    });
    if (diagnosis) {
      final tcp = _object(_object(facts['observations'])['tcp']);
      final identity = _object(facts['identity']);
      final device = _object(facts['device']);
      final settings = await _request('settings.get', {});
      await _verifyFacts(facts, params['deviceId']);
      return {
        ...facts,
        'tcpReachable': tcp['status'] == 'ok'
            ? true
            : tcp['status'] == 'error' && tcp['code'] != 'permission_denied'
            ? false
            : null,
        'networkError': tcp['code'],
        'identityPresent': identity['status'] == 'ok'
            ? true
            : identity['status'] == 'error'
            ? false
            : null,
        'identityError': identity['code'],
        'adbBurstRequested': settings['adbBurstMode'] == true,
        'wirelessProperties': _object(
          _object(facts['observations'])['wirelessProperties'],
        )['stdout'],
        'notes': [
          if (tcp['code'] == 'permission_denied')
            '主控网络权限未允许，请先检查系统权限；手填地址不能绕过权限。',
          if (device['transport'] == 'tls') '配对端口与连接端口不同。',
          'mDNS 不可用时仍可手动填写可达的连接地址。',
          '网络可达、已配对与设备连接是独立状态。',
        ],
      };
    }
    if (command != 'device.capabilities') {
      throw const InteropException('unknown_command', '未知设备解释请求。');
    }
    final device = _object(facts['device']);
    final api = device['apiLevel'] as int?;
    final connected = facts['connected'] == true;
    final observations = _object(facts['observations']);
    final companion = _object(facts['companion']);
    final activities = _object(facts['activities']);
    final audio = _object(facts['audio']);
    final entries = <SetupJson>[];
    void add(String id, String status, String reason) => entries.add({
      'id': id,
      'key': id,
      'name': id,
      'status': status,
      'reason': reason,
    });
    bool observed(String name) => _object(observations[name])['status'] == 'ok';
    final shell = _object(observations['shell']);
    add(
      'shell',
      !connected
          ? 'unknown'
          : observed('shell') && shell['stdout'] == 'interop-capability-check'
          ? 'available'
          : 'limited',
      !connected
          ? '设备尚未连接，无法探测。'
          : observed('shell') && shell['stdout'] == 'interop-capability-check'
          ? '已通过当前设备授权连接验证 shell。'
          : 'ADB 已连接，但 shell 探测未成功。',
    );
    add(
      'files',
      !connected
          ? 'unknown'
          : observed('sync')
          ? 'available'
          : 'limited',
      !connected
          ? '设备尚未连接，无法探测。'
          : observed('sync')
          ? '已通过当前连接验证文件服务；受 Android 文件权限限制。'
          : '当前文件服务探测失败，可查看连接诊断。',
    );
    add(
      'wirelessPairing',
      api != null && api < 30
          ? 'unavailable'
          : device['guid'] != null
          ? 'available'
          : api == null
          ? 'unknown'
          : 'needsSetup',
      api != null && api < 30
          ? '设备 Android 版本低于 11，可使用授权 USB 开启 IP 连接。'
          : device['guid'] != null
          ? '已配对；当前连接状态单独判断。'
          : api == null
          ? '尚未读取 Android 版本，无线配对能力待确认。'
          : '请在被控设备开启无线调试并完成配对。',
    );
    final sessions = activities['sessions'] as List? ?? const [];
    final streaming = sessions
        .map(_object)
        .any(
          (s) =>
              s['deviceId'] == params['deviceId'] && s['status'] == 'streaming',
        );
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
    final clipboard = _object(companion['clipboard']);
    add(
      'clipboard',
      api != null && api < 21
          ? 'unavailable'
          : !connected
          ? 'unknown'
          : clipboard['status'] as String? ?? 'unknown',
      api != null && api < 21
          ? '互联文本通道需要 Android 5.0 或更新版本。'
          : clipboard['reason'] as String? ?? '文本通道按实际探测与本机前台权限判断。',
    );
    final packages = _object(observations['packages']);
    final packageReadable =
        observed('packages') &&
        (packages['exitCode'] == null || packages['exitCode'] == 0) &&
        packages['stdout'] is String &&
        (packages['stdout'] as String).startsWith('package:');
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
    final playing = (audio['sources'] as List? ?? const [])
        .map(_object)
        .any(
          (source) =>
              source['deviceId'] == params['deviceId'] &&
              source['status'] == 'playing' &&
              source['nativeAttached'] == true,
        );
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
    // Host capability queries can await; discard facts from a replaced device.
    await _verifyFacts(facts, params['deviceId']);
    return {
      'deviceId': params['deviceId'],
      'connectionId': facts['connectionId'],
      'capabilities': entries,
      'features': facts['features'] ?? const <Object?>[],
    };
  }

  Future<void> _verifyFacts(SetupJson facts, Object? id) async {
    final latest = await _request('devices.list', {});
    final current = (latest['devices'] as List? ?? const [])
        .map(_object)
        .where((d) => d['id'] == id)
        .firstOrNull;
    final device = _object(facts['device']);
    if (current == null ||
        current['connectionId'] != facts['connectionId'] ||
        [
          'address',
          'port',
          'transport',
          'guid',
        ].any((key) => current[key] != device[key])) {
      throw const InteropException('stale_connection', '检查期间设备连接或地址已改变，请重新检查。');
    }
  }
}

SetupJson _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
