import 'dart:convert';

import 'system_notice.dart';

/// 只向系统交付定位信息，不把它作为授权回执。
class SystemNotificationTarget {
  const SystemNotificationTarget({
    required this.kind,
    required this.deviceId,
    required this.objectId,
    required this.revision,
    required this.observationGeneration,
  });
  final SystemNotificationKind kind;
  final String deviceId;
  final String objectId;
  final String revision;
  final int observationGeneration;

  String encode() => jsonEncode({
    'v': 1,
    'kind': kind.name,
    'deviceId': deviceId,
    'objectId': objectId,
    'revision': revision,
    'observationGeneration': observationGeneration,
  });

  static SystemNotificationTarget? decode(String payload) {
    if (payload.length > 4096) return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic> || data['v'] != 1) return null;
      final kind = SystemNotificationKind.values
          .where((kind) => kind.name == data['kind'])
          .firstOrNull;
      final generation = data['observationGeneration'];
      if (kind == null || generation is! int || generation < 0) return null;
      for (final key in ['deviceId', 'objectId', 'revision']) {
        if (data[key] is! String ||
            (data[key] as String).isEmpty ||
            (data[key] as String).length > 512) {
          return null;
        }
      }
      return SystemNotificationTarget(
        kind: kind,
        deviceId: data['deviceId'] as String,
        objectId: data['objectId'] as String,
        revision: data['revision'] as String,
        observationGeneration: generation,
      );
    } catch (_) {
      return null;
    }
  }
}

class SystemNotificationActivation {
  const SystemNotificationActivation({
    required this.target,
    required this.available,
    this.reason = '',
  });
  final SystemNotificationTarget target;
  final bool available;
  final String reason;
}
