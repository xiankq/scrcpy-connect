import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/control/video_quality_policy.dart';
import 'package:scrcpy_connect/core/control/virtual_display_policy.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/core/settings/preference_schema.dart';

void main() {
  test('新设备默认使用界面所列的 720P，保留旧设备的自定义上限', () {
    final settings = Preferences(
      deviceQuality: {'old': const VideoQualityPreferences(maxSize: 1280)},
    );
    expect(VideoQualityPolicy.resolveQuality(settings, 'new').maxSize, 720);
    expect(VideoQualityPolicy.resolveQuality(settings, 'old').maxSize, 1280);
  });

  test('原画可保存、还原并将无限制尺寸交给画面启动', () {
    final selected = VideoQualityPolicy.resolveQuality(
      Preferences(),
      'device',
      const VideoQualityPatch(maxSize: 0),
    );
    final encoded = PreferenceCodec.encodeQuality(selected.preferences);
    PreferenceSchema(defaults: const {}).validate(encoded);
    final settings = Preferences(
      deviceQuality: {'device': PreferenceCodec.decodeQuality(encoded)},
    );
    final original = VideoQualityPolicy.resolveQuality(settings, 'device');
    expect(original.maxSize, 0);
    expect(
      VirtualDisplayPolicy.fit((width: 1400, height: 2800), original.maxSize),
      (width: 1400, height: 2800),
    );
  });
}
