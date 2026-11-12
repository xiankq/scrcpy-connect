/// 应用内事实和意图的共有元数据；具体数据契约由所属能力定义。
abstract class AppEvent {
  const AppEvent();

  String get type;
  String? get deviceId => null;
  bool get telemetry => false;

  RuntimeEvent toApplicationEvent({int? sequence}) =>
      RuntimeEvent(this, sequence: sequence);
}

/// 唯一事件所有者登记的交付；恢复、意图和呈现回执不占用业务序列。
final class RuntimeEvent {
  const RuntimeEvent(this.data, {this.sequence})
    : assert(sequence == null || sequence >= 0);

  final AppEvent data;
  final int? sequence;
  String get type => data.type;
  String? get deviceId => data.deviceId;
  bool get telemetry => data.telemetry;
}
