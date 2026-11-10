import 'dart:async';

import 'package:scrcpy_connect/widgets/command_query.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CommandView extends HookWidget {
  const CommandView({
    super.key,
    required this.controller,
    required this.command,
    this.params = const {},
    required this.builder,
    this.emptyTitle = '暂时没有内容',
    this.alternative,
    this.refreshKey,
  });
  final AppStore controller;
  final String command;
  final Json params;
  final Widget Function(BuildContext, Json, VoidCallback) builder;
  final String emptyTitle;
  final Widget? alternative;
  final Object? refreshKey;
  @override
  Widget build(BuildContext context) {
    final query = useMemoized(
      () => CommandQuery(
        request: controller.request,
        events: controller.eventStream(),
        command: command,
        params: params,
      ),
      [controller, command, params.toString()],
    );
    useListenable(query);
    useEffect(() => query.dispose, [query]);
    final previousRefresh = useRef(refreshKey);
    useEffect(() {
      if (previousRefresh.value != refreshKey) {
        previousRefresh.value = refreshKey;
        unawaited(query.refresh());
      }
      return null;
    }, [query, refreshKey]);
    void refresh() => unawaited(query.refresh());
    if (query.loading && query.data == null) {
      return const PageChromeBody(
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (query.error != null) {
      return PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.circleAlert,
          title: emptyTitle,
          message: '${query.error}',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: refresh,
                icon: const Icon(
                  LucideIcons.refreshCw,
                  size: DesignTokens.componentIconActionSize,
                ),
                label: const Text('重新检查'),
              ),
              ?alternative,
            ],
          ),
        ),
      );
    }
    return builder(context, query.data ?? {}, refresh);
  }
}
