import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/mobile_remote_capabilities.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final pane = RemoteWindowScope.of(context)?.pane;
    final mobile = MobileRemoteScope.maybeOf(context);
    return PageFrame(
      title: '暂时无法打开',
      child: PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.fileQuestionMark,
          title: '这项内容当前不可用',
          message: message,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignTokens.spacingSm,
            children: [
              AppButton(
                role: AppButtonRole.primary,
                onPressed: mobile != null
                    ? () => mobile.close()
                    : pane == null
                    ? () => const DevicesRoute().go(context)
                    : () => RemoteWindows.maybeOf(context)?.remove(pane),
                label: pane == null && mobile == null ? '返回设备列表' : '关闭窗口',
              ),
              if (onRetry != null)
                AppButton(
                  role: AppButtonRole.secondaryOnPage,
                  onPressed: onRetry,
                  label: '重新读取',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
