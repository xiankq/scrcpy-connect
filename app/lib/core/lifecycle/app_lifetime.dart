/// 当前应用所有者的单向准入；开始关闭即结束，资源释放失败不会重新开放。
/// 在功能装配前创建，能力读取准入时无需反向取得生命周期协调器。
final class AppLifetime {
  bool _ended = false;
  bool get ended => _ended;

  void end() => _ended = true;
}
