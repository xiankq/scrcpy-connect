import 'package:flutter/foundation.dart';

typedef NotificationReplyKey = ({
  String deviceId,
  String notificationId,
  String revision,
});

enum NotificationReplyPhase {
  editing,
  submitting,
  unknown,
  accepted,
  submitted,
}

/// Ephemeral content and submission guard for one exact original action.
/// This contains no notification history and is never persisted or backed up.
@immutable
class NotificationReplyState {
  const NotificationReplyState({
    this.text = '',
    this.phase = NotificationReplyPhase.editing,
    this.message = '',
    this.expired = false,
  });

  final String text;
  final NotificationReplyPhase phase;
  final String message;
  final bool expired;
  bool get canEdit => phase == NotificationReplyPhase.editing && !expired;

  NotificationReplyState copyWith({
    String? text,
    NotificationReplyPhase? phase,
    String? message,
    bool? expired,
  }) => NotificationReplyState(
    text: text ?? this.text,
    phase: phase ?? this.phase,
    message: message ?? this.message,
    expired: expired ?? this.expired,
  );
}

Map<NotificationReplyKey, NotificationReplyState> expireNotificationReplies(
  Map<NotificationReplyKey, NotificationReplyState> entries,
  String deviceId,
  Map<String, dynamic> snapshot,
) {
  if (snapshot['live'] != true || snapshot['notifications'] is! List<Object?>) {
    return entries;
  }
  final notifications = (snapshot['notifications'] as List<Object?>)
      .whereType<Map<Object?, Object?>>();
  final complete =
      snapshot['truncated'] != true &&
      ['available', 'limited'].contains(snapshot['status']);
  return {
    for (final entry in entries.entries)
      entry.key:
          entry.key.deviceId == deviceId &&
              !entry.value.expired &&
              (notifications.any(
                    (item) =>
                        item['id'] == entry.key.notificationId &&
                        ((item['revision'] ?? item['id']) !=
                                entry.key.revision ||
                            item['canReply'] == false),
                  ) ||
                  (complete &&
                      !notifications.any(
                        (item) => item['id'] == entry.key.notificationId,
                      )))
          ? entry.value.copyWith(expired: true)
          : entry.value,
  };
}

Map<NotificationReplyKey, NotificationReplyState> repliesForDevices(
  Map<NotificationReplyKey, NotificationReplyState> entries,
  Iterable<String> deviceIds,
) {
  final retained = deviceIds.toSet();
  return {
    for (final entry in entries.entries)
      if (retained.contains(entry.key.deviceId)) entry.key: entry.value,
  };
}
