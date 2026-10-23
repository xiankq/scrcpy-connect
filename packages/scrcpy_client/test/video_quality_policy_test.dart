import 'package:flutter_test/flutter_test.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

void main() {
  test(
    'Dart resolves defaults, device choices and explicit request in order',
    () {
      final settings = <String, dynamic>{
        ...defaultVideoQuality,
        'videoCodec': 'av1',
        'deviceQuality': {
          'a': {'videoCodec': 'h265', 'maxSize': 1920},
          'b': {'videoCodec': 'vp9'},
        },
      };
      final before = settings.toString();
      final a = VideoQualityPolicy.resolve(settings, 'a', {'maxFps': 24});
      expect(a['videoCodec'], 'h265');
      expect(a['maxSize'], 1920);
      expect(a['maxFps'], 24);
      expect(VideoQualityPolicy.resolve(settings, 'b')['videoCodec'], 'vp9');
      expect(VideoQualityPolicy.resolve(settings, 'c')['videoCodec'], 'av1');
      expect(settings.toString(), before);
    },
  );

  test(
    'presets expand in Dart and explicit values override the chosen preset',
    () {
      final overridden = VideoQualityPolicy.resolve({}, null, {
        'preset': 'smooth',
        'bitRate': 5000000,
        'codec': 'vp8',
        'encoder': null,
      });
      expect(overridden['videoBitRate'], 5000000);
      expect(overridden['videoCodec'], 'vp8');
      expect(overridden['videoEncoder'], isNull);
      expect(
        () => VideoQualityPolicy.resolve({}, null, {'preset': 'bogus'}),
        throwsA(isA<InteropException>()),
      );
    },
  );

  test('balanced defaults to the four-megabit network-safe profile', () {
    final balanced = VideoQualityPolicy.resolve({}, null);
    expect(balanced['maxSize'], 1280);
    expect(balanced['maxFps'], 60);
    expect(balanced['videoBitRate'], 4000000);

    final options = VideoQualityPolicy.options({}, {}, null);
    final bitRates = (options['bitRate'] as List)
        .map((entry) => (entry as Map)['value'])
        .toList();
    expect(bitRates, contains(4000000));
  });
}
