import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_record.dart';

/// 本次实际属性查询的结果；空值表示未知，不以设备记录或连接选择器补齐。
final class DeviceFacts {
  const DeviceFacts({
    this.serial,
    this.bootSerial,
    this.model,
    this.androidVersion,
    this.apiLevel,
    this.guid,
  });

  /// 本次 ro.serialno；与 ro.boot.serialno 分别保存，不能跨属性冒充同一身份。
  final String? serial;
  final String? bootSerial;
  final String? model;
  final String? androidVersion;
  final int? apiLevel;
  final String? guid;

  /// 普通重连拒绝已知冲突；修改配置或重新授权还须核验原记录的真实序列号。
  /// 缺失事实不证明原缓存有效；本方法不更新记录，也不证明主控密钥或 TLS 信任。
  void assertMatches(DeviceRecord record, {bool requireKnownSerial = false}) {
    if (record.serial != null && serial != null && record.serial != serial ||
        record.guid != null && guid != null && record.guid != guid) {
      throw const RequestFailure(
        'device_identity_mismatch',
        '连接目标与原设备身份不符，请核对设备。',
      );
    }
    if (requireKnownSerial && (record.serial == null || serial == null)) {
      throw const RequestFailure(
        'device_identity_unverified',
        '无法核验原设备身份，请检查设备授权与连接。',
      );
    }
  }
}
