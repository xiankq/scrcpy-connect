import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:material_ui/material_ui.dart';

/// 主题或事件重建时保留同一次查询及其页面。
class RouteResourceView<T extends Object> extends StatefulWidget {
  const RouteResourceView({
    super.key,
    required this.identity,
    required this.load,
    required this.builder,
    this.preserveContent = false,
  });
  final String identity;
  final bool preserveContent;
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  @override
  State<RouteResourceView<T>> createState() => _RouteResourceViewState<T>();
}

class _RouteResourceViewState<T extends Object>
    extends State<RouteResourceView<T>> {
  late Future<T> resource = widget.load();
  Widget? content;
  @override
  void didUpdateWidget(RouteResourceView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      resource = widget.load();
      content = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    key: ValueKey(widget.identity),
    future: resource,
    builder: (context, snapshot) {
      final waiting = !snapshot.hasData && !snapshot.hasError;
      final Widget child;

      if (snapshot.hasError) {
        child = RouteErrorPage(
          message: failureMessage(
            snapshot.error,
            fallback: '无法打开此页面。请返回上一页后重试。',
          ),
          onRetry: () => setState(() => resource = widget.load()),
        );
      } else if (waiting) {
        child = const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        );
      } else if (widget.preserveContent) {
        // 路由刷新可能重新解析 extra；已附着画面保留原打开决定，并继续拥有会话。
        child = content ??= widget.builder(context, snapshot.data!);
      } else {
        child = widget.builder(context, snapshot.data!);
      }
      return ContentArrival(
        state: snapshot.connectionState,
        waiting: waiting,
        child: child,
      );
    },
  );
}
