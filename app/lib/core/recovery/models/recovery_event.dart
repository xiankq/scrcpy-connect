import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';

sealed class RecoveryEvent {
  const RecoveryEvent();
}

final class RecoveryStarted extends RecoveryEvent {
  const RecoveryStarted();
}

final class RecoveryCompleted extends RecoveryEvent {
  const RecoveryCompleted(this.snapshot);
  final RuntimeSnapshot snapshot;
}

final class RecoveryFailed extends RecoveryEvent {
  const RecoveryFailed(this.reason);
  final String reason;
}
