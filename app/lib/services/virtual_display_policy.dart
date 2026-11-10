typedef DisplayJson = Map<String, dynamic>;

/// scrcpy flex display 分别限制每个轴；传入具体像素前，先在当前编码器上限内求解产品宽高比。
class VirtualDisplayPolicy {
  static DisplayJson fit(DisplayJson params, Object? maxSize) {
    final hasSize =
        params.containsKey('displayWidth') ||
        params.containsKey('displayHeight');
    final width = hasSize ? params['displayWidth'] : 1080;
    final height = hasSize ? params['displayHeight'] : 1920;
    if (width is! int ||
        height is! int ||
        width < 2 ||
        height < 2 ||
        width > 4096 ||
        height > 4096 ||
        maxSize is! int ||
        maxSize < 320 ||
        maxSize > 4096) {
      // 格式错误的执行参数交由原生执行入口核验。
      return params;
    }
    final longest = width > height ? width : height;
    final limit = maxSize ~/ 2 * 2;
    int scaled(int side, int ceiling) {
      final even = (side * ceiling + longest) ~/ (2 * longest) * 2;
      return even < 2 ? 2 : even;
    }

    var fittedWidth = width;
    var fittedHeight = height;
    if (longest > limit) {
      fittedWidth = scaled(width, limit);
      fittedHeight = scaled(height, limit);
      final ratio = width / height;
      // 极窄自动视口的短边取整可能损失比例精度；优先选择比例误差在 0.5% 且绝对误差在 0.008 内的最大偶数尺寸。
      // 像素不足时保留最大尺寸。
      for (var ceiling = limit; ceiling >= 2; ceiling -= 2) {
        final candidateWidth = scaled(width, ceiling);
        final candidateHeight = scaled(height, ceiling);
        final error = (candidateWidth / candidateHeight - ratio).abs();
        if (error <= .008 && error / ratio <= .005) {
          fittedWidth = candidateWidth;
          fittedHeight = candidateHeight;
          break;
        }
      }
    }
    return {
      ...params,
      'displayWidth': fittedWidth,
      'displayHeight': fittedHeight,
    };
  }

  static Future<DisplayJson> prepare(
    String command,
    DisplayJson params, {
    required Future<DisplayJson> Function(DisplayJson) readSessions,
  }) async {
    if ((command == 'apps.launch' || command == 'session.start') &&
        params['packageName'] is String) {
      return fit(params, params['maxSize']);
    }
    if (command != 'session.display' ||
        !params.containsKey('displayWidth') ||
        !params.containsKey('displayHeight')) {
      return params;
    }
    final facts = await readSessions({
      if (params['deviceId'] != null) 'deviceId': params['deviceId'],
    });
    final candidates = (facts['sessions'] as List? ?? const [])
        .whereType<DisplayJson>()
        .where(
          (session) => params['sessionId'] != null
              ? session['sessionId'] == params['sessionId']
              : session['deviceId'] == params['deviceId'],
        )
        .toList();
    if (candidates.length != 1 || candidates.single['packageName'] is! String) {
      return params;
    }
    // 按当前代际实际应用的画质调整尺寸；画质重建失败时，可能为明确重试保留旧代际。
    final quality = candidates.single['quality'] as Map?;
    return fit(params, quality?['maxSize']);
  }
}
