import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
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
  final AppController controller;
  final String command;
  final Json params;
  final Widget Function(BuildContext, Json, VoidCallback) builder;
  final String emptyTitle;
  final Widget? alternative;
  final Object? refreshKey;
  @override
  Widget build(BuildContext context) {
    final retry = useState(0);
    final future = useMemoized(() => controller.request(command, params), [
      command,
      params.toString(),
      retry.value,
      refreshKey,
    ]);
    final identity = '$command:${params.toString()}';
    final previousIdentity = useRef(identity);
    final changedObject = previousIdentity.value != identity;
    previousIdentity.value = identity;
    final result = useFuture(future, preserveState: !changedObject);
    if (result.connectionState != ConnectionState.done && !result.hasData) {
      return const PageChromeBody(
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (result.hasError) {
      return PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.circleAlert,
          title: emptyTitle,
          message: '${result.error}',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => retry.value++,
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
    return builder(context, result.data ?? {}, () => retry.value++);
  }
}
