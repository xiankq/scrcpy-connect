/// 应用内事实和意图的共有元数据；具体数据契约由所属能力定义。
abstract class AppEvent {
  const AppEvent();

  String get type;
  String? get deviceId => null;

  /// 兼容现有事件传输，负载保留原类型，不进行 JSON 编解码。
  Map<String, dynamic> toApplicationEvent() => {
    'type': type,
    'deviceId': ?deviceId,
    'data': this,
  };
}
