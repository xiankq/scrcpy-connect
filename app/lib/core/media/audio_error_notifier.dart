import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';

part 'audio_error_notifier.g.dart';

@Riverpod(keepAlive: true)
class AudioErrorNotifier extends _$AudioErrorNotifier {
  @override
  String? build() =>
      ref.watch(stateSubscriptionProvider).session.initialState.audioError;

  void update(String? error) {
    if (ref.mounted && state != error) state = error;
  }
}
