import 'remote_control_intent.dart';

/// 创建画面的明确请求只短暂保留，不携带控件、授权或长期信任，恢复 URL 不能重建请求。
class RemoteLaunchIntent {
  const RemoteLaunchIntent({this.action});
  final RemoteControlIntent? action;
}
