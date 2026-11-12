import 'preferences.dart';
import 'preference_codec.dart';

/// 持久化版本与已校验的偏好；序列化只在存储和迁移边界执行。
final class SettingsSnapshot {
  const SettingsSnapshot(this.revision, this.values);
  final int revision;
  final Preferences values;
  Map<String, Object?> toMap() => PreferenceCodec.encode(values);
}
