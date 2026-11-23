import 'package:flutter/widgets.dart';

/// 路由与导航从首帧可用，依赖应用会话的内容在各自页面等待绑定。
class AppSessionScope extends InheritedWidget {
  const AppSessionScope({
    super.key,
    required this.ready,
    required this.failure,
    required this.onRetry,
    required super.child,
  });

  final bool ready;
  final String? failure;
  final VoidCallback onRetry;

  static AppSessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSessionScope>();

  @override
  bool updateShouldNotify(AppSessionScope oldWidget) =>
      ready != oldWidget.ready || failure != oldWidget.failure;
}
