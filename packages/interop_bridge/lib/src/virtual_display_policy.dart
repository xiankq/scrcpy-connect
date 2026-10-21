typedef DisplayJson = Map<String, dynamic>;

/// scrcpy flex displays constrain each axis separately. Resolve the product's
/// aspect ratio within the active encoder limit before sending concrete pixels.
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
      // Leave malformed execution parameters to the native validation boundary.
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
      // Very narrow auto viewports can lose substantial aspect precision when
      // rounding the short side. Prefer the largest even pair within 0.5% and
      // 0.008 absolute ratio error; keep the maximum pair if pixels cannot fit.
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
    // Resize against the quality this generation actually applied. A failed
    // quality rebuild may retain an older generation for an explicit retry.
    final quality = candidates.single['quality'] as Map?;
    return fit(params, quality?['maxSize']);
  }
}
