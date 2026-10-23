import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_protocol/device_protocol.dart';

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
      expect(
        CoreRequest(InteropCommand.transfersCancel, {
          'batchId': 'batch',
        }).encode(),
        contains('"batchId":"batch"'),
      );
      expect(
        CoreRequest(InteropCommand.transfersCancel, {
          'transferId': 'item',
        }).encode(),
        contains('"transferId":"item"'),
      );
      expect(
        () => CoreRequest(InteropCommand.sessionStart, {
          'deviceId': 'a',
          'packageName': 7,
        }),
        failure('invalid_argument'),
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

  test('composed state remains subject to the full public contract', () {
    final request = CoreRequest(InteropCommand.transfersList);
    const raw = '{"protocolVersion":1,"ok":true,"data":{}}';
    expect(() => request.decodeResponse(raw), failure('invalid_response'));
    expect(
      request.decodeResponse(
        raw,
        compose: (native) => {...native, 'transfers': <Object?>[]},
      ),
      {'transfers': <Object?>[]},
    );
    expect(
      () => request.decodeResponse(
        raw,
        compose: (native) => {...native, 'transfers': 'invalid'},
      ),
      failure('invalid_response'),
    );
    var called = false;
    expect(
      () => request.decodeResponse(
        '{"protocolVersion":2,"ok":true,"data":{}}',
        compose: (native) {
          called = true;
          return {'transfers': <Object?>[]};
        },
      ),
      failure('protocol_version'),
    );
    expect(called, isFalse);
  });

  test('request cap counts UTF-8 bytes on both sides of the wire', () {
    final request = CoreRequest(InteropCommand.sessionText, {
      'sessionId': 'a',
      'text': List.filled(400000, '字').join(),
    });
    expect(request.encode, failure('request_limit'));
  });
}
