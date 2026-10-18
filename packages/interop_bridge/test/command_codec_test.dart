import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/protocol/command_codec.dart';

Matcher failure(String code) =>
    throwsA(isA<InteropException>().having((e) => e.code, 'code', code));

void main() {
  test(
    'one contract validates names and fields before entering native code',
    () {
      expect(
        () => CoreRequest.named('devices.lsit'),
        failure('unknown_command'),
      );
      expect(
        () => CoreRequest(InteropCommand.devicesConnect, {'deviceId': 1}),
        failure('invalid_argument'),
      );
      expect(
        () => CoreRequest(InteropCommand.devicesConnect, {'deviceId': ''}),
        failure('invalid_argument'),
      );
      expect(
        () => CoreRequest(InteropCommand.documentsImportFiles),
        failure('unknown_command'),
      );
      final request = CoreRequest(InteropCommand.devicesConnect, {
        'deviceId': 'a',
      });
      expect(jsonDecode(request.encode()), {
        'protocolVersion': 1,
        'command': 'devices.connect',
        'params': {'deviceId': 'a'},
      });
    },
  );

  test(
    'preserves device selectors and global next-session quality settings',
    () {
      expect(
        CoreRequest(InteropCommand.sessionPause, {'deviceId': 'device'}).params,
        {'deviceId': 'device'},
      );
      expect(
        CoreRequest(InteropCommand.sessionQuality, {
          'videoCodec': 'h264',
        }).params,
        {'videoCodec': 'h264'},
      );
      expect(
        CoreRequest(InteropCommand.mediaCacheConfigure, {
          'budgetBytes': 5000,
        }).params,
        {'budgetBytes': 5000},
      );
    },
  );

  test(
    'malformed successes cannot silently become empty successful results',
    () {
      final request = CoreRequest(InteropCommand.devicesList);
      for (final raw in [
        'not json',
        '[]',
        '{"protocolVersion":1,"ok":"true","data":{}}',
        '{"protocolVersion":1,"ok":true,"data":null}',
        '{"protocolVersion":1,"ok":true,"data":{"device":[]}}',
        '{"protocolVersion":1,"ok":false,"error":{"message":"failed"}}',
      ]) {
        expect(() => request.decodeResponse(raw), failure('invalid_response'));
      }
      expect(
        () =>
            request.decodeResponse('{"protocolVersion":2,"ok":true,"data":{}}'),
        failure('protocol_version'),
      );
      expect(
        request.decodeResponse(
          '{"protocolVersion":1,"ok":true,"data":{"devices":[]}}',
        ),
        {'devices': <Object?>[]},
      );
    },
  );

  test('domain errors retain code and exact recovery details', () {
    final request = CoreRequest(InteropCommand.sessionStart, {'deviceId': 'a'});
    expect(
      () => request.decodeResponse(
        jsonEncode({
          'protocolVersion': 1,
          'ok': false,
          'error': {
            'code': 'app_launch_unknown',
            'message': 'verify',
            'details': {'sessionId': 'old', 'launchOutcome': 'unknown'},
          },
        }),
      ),
      throwsA(
        isA<InteropException>()
            .having((e) => e.code, 'code', 'app_launch_unknown')
            .having((e) => e.details, 'details', {
              'sessionId': 'old',
              'launchOutcome': 'unknown',
            }),
      ),
    );
  });

  test('request cap counts UTF-8 bytes on both sides of the wire', () {
    final request = CoreRequest(InteropCommand.sessionText, {
      'sessionId': 'a',
      'text': List.filled(400000, '字').join(),
    });
    expect(request.encode, failure('request_limit'));
  });
}
