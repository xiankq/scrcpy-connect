import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

void main() {
  test('virtual launch fits both axes while preserving the selected ratio', () {
    for (final (width, height) in [
      (1280, 1920),
      (1920, 1280),
      (1080, 1920),
      (1920, 1080),
      (384, 1920),
      (1920, 384),
      (4096, 320),
      (320, 4096),
    ]) {
      for (final limit in [320, 720, 1280, 1920]) {
        final params = {'displayWidth': width, 'displayHeight': height};
        final result = VirtualDisplayPolicy.fit(params, limit);
        final w = result['displayWidth'] as int;
        final h = result['displayHeight'] as int;
        expect(w, inInclusiveRange(2, limit));
        expect(h, inInclusiveRange(2, limit));
        expect(w.isEven && h.isEven, isTrue);
        expect(w / h, closeTo(width / height, .008));
        expect((w / h / (width / height) - 1).abs(), lessThanOrEqualTo(.005));
        expect(params['displayWidth'], width);
        expect(params['displayHeight'], height);
      }
    }
    expect(
      VirtualDisplayPolicy.fit({
        'displayWidth': 1280,
        'displayHeight': 1920,
      }, 1280),
      {'displayWidth': 854, 'displayHeight': 1280},
    );
    expect(VirtualDisplayPolicy.fit({}, 1280), {
      'displayWidth': 720,
      'displayHeight': 1280,
    });
    expect(
      VirtualDisplayPolicy.fit({
        'displayWidth': 4096,
        'displayHeight': 320,
      }, 320),
      {'displayWidth': 256, 'displayHeight': 20},
    );
  });

  test('resizing uses the exact retained virtual session quality', () async {
    final requests = <DisplayJson>[];
    Future<DisplayJson> read(DisplayJson filter) async {
      requests.add(filter);
      return {
        'sessions': [
          {
            'sessionId': 'phone',
            'deviceId': 'a',
            'packageName': null,
            'quality': {'maxSize': 320},
          },
          {
            'sessionId': 'app',
            'deviceId': 'a',
            'packageName': 'com.example.app',
            'quality': {'maxSize': 720},
          },
        ],
      };
    }

    final params = <String, dynamic>{
      'sessionId': 'app',
      'deviceId': 'a',
      'displayWidth': 1280,
      'displayHeight': 1920,
      'maxSize': 1920,
    };
    for (final malformed in <DisplayJson>[
      {'sessionId': 'app', 'deviceId': 'a'},
      {'sessionId': 'app', 'deviceId': 'a', 'displayWidth': 640},
    ]) {
      expect(
        await VirtualDisplayPolicy.prepare(
          'session.display',
          malformed,
          readSessions: read,
        ),
        same(malformed),
      );
    }
    expect(requests, isEmpty);
    final app = await VirtualDisplayPolicy.prepare(
      'session.display',
      params,
      readSessions: read,
    );
    expect(app['displayWidth'], 480);
    expect(app['displayHeight'], 720);
    expect(requests.single, {'deviceId': 'a'});
    final phoneParams = {...params, 'sessionId': 'phone'};
    expect(
      await VirtualDisplayPolicy.prepare(
        'session.display',
        phoneParams,
        readSessions: read,
      ),
      same(phoneParams),
    );
    final ambiguous = {...params}..remove('sessionId');
    expect(
      await VirtualDisplayPolicy.prepare(
        'session.display',
        ambiguous,
        readSessions: read,
      ),
      same(ambiguous),
    );
  });
}
