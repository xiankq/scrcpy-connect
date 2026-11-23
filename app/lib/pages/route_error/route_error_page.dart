import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final pane = RemoteWindowScope.of(context)?.pane;
    return PageFrame(
      title: '暂时无法打开',
      child: PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.fileQuestionMark,
          title: '这项内容当前不可用',
          message: message,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null)
                OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
              FilledButton(
                onPressed: pane == null
                    ? () => const DevicesRoute().go(context)
                    : () => RemoteWindows.maybeOf(context)?.remove(pane),
                child: Text(pane == null ? '返回设备列表' : '关闭窗口'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
