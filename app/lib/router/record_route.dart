import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';

/// Keeps one lookup and the resulting page alive across theme/event rebuilds.
class RecordRoute extends StatefulWidget {
  const RecordRoute({
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
  State<RecordRoute> createState() => _RecordRouteState();
}

class _RecordRouteState extends State<RecordRoute> {
  late Future<Json> record = widget.load();
  Widget? content;
  @override
  void didUpdateWidget(RecordRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      record = widget.load();
      content = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    key: ValueKey(widget.identity),
    future: record,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RouteErrorPage(
          message: '${snapshot.error}',
          onRetry: () => setState(() => record = widget.load()),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      if (widget.preserveContent) {
        // A router refresh can decode extras again. An already attached live
        // surface keeps its original launch decision and owns its session.
        return content ??= widget.builder(context, snapshot.data!);
      }
      return widget.builder(context, snapshot.data!);
    },
  );
}
