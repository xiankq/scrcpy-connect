import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:flutter/material.dart';

/// 主题或事件重建时保留同一次查询及其页面。
class RouteResourceView extends StatefulWidget {
  const RouteResourceView({
    super.key,
    required this.identity,
    required this.load,
    required this.builder,
    this.preserveContent = false,
  });
  final String identity;
  final bool preserveContent;
  final Future<Json> Function() load;
  final Widget Function(BuildContext, Json) builder;
  @override
  State<RouteResourceView> createState() => _RouteResourceViewState();
}

class _RouteResourceViewState extends State<RouteResourceView> {
  late Future<Json> resource = widget.load();
  Widget? content;
  @override
  void didUpdateWidget(RouteResourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      resource = widget.load();
      content = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    key: ValueKey(widget.identity),
    future: resource,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RouteErrorPage(
          message: '${snapshot.error}',
          onRetry: () => setState(() => resource = widget.load()),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      if (widget.preserveContent) {
        // 路由刷新可能重新解析 extra；已附着画面保留原打开决定，并继续拥有会话。
        return content ??= widget.builder(context, snapshot.data!);
      }
      return widget.builder(context, snapshot.data!);
    },
  );
}
