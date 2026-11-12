import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';

/// 状态提交后的事件流；查询借用订阅，不拥有应用传输及其关闭责任。
final runtimeEventsProvider = Provider<Stream<RuntimeEvent>>(
  (ref) => ref.watch(stateSubscriptionProvider).events,
);
