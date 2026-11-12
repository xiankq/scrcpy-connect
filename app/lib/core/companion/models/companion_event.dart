import 'package:scrcpy_connect/core/events/models/app_event.dart';

sealed class CompanionEvent extends AppEvent {
  const CompanionEvent(this.deviceId, this.connectionId);
  @override
  final String deviceId;
  final String connectionId;
}

final class CompanionStarting extends CompanionEvent {
  const CompanionStarting(super.deviceId, super.connectionId);
  @override
  String get type => 'companion.starting';
}

final class CompanionReady extends CompanionEvent {
  const CompanionReady(
    super.deviceId,
    super.connectionId, {
    required this.protocol,
    this.apiLevel,
  });
  final int protocol;
  final int? apiLevel;
  @override
  String get type => 'companion.ready';
}

final class CompanionStopped extends CompanionEvent {
  const CompanionStopped(super.deviceId, super.connectionId);
  @override
  String get type => 'companion.stopped';
}
