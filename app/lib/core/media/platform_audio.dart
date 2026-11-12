import 'dart:io';

import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_focus_service.dart';

/// Android 系统音频协议及其他宿主的本机混音租约适配。
final class PlatformAudio {
  PlatformAudio({required this._request});
  final Future<Json> Function(String, Json) _request;
  late final _mixer = AudioFocusService(
    backgroundPlaybackSupported: !Platform.isIOS,
  );

  Future<Json> request(String command, Json params) async {
    try {
      if (!Platform.isAndroid && command.startsWith('audio.platform.')) {
        return await _mixer.request(command, params);
      }
      return await _request(command, params);
    } on PlatformException catch (error) {
      throw RequestFailure(error.code, error.message ?? '系统声音操作未完成。');
    }
  }

  Future<bool> readVisible() async =>
      (await _request('audio.platform.state', const {}))['visible'] == true;
}
