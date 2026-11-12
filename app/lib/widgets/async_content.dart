import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';

/// 读取过程保留已有内容；首次加载、失败及重试由视图呈现。
class AsyncContent<T extends Object> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.loading,
    required this.data,
    required this.error,
    required this.onRefresh,
    required this.builder,
    this.emptyTitle = '暂时没有内容',
    this.alternative,
  });

  final bool loading;
  final T? data;
  final Object? error;
  final VoidCallback onRefresh;
  final Widget Function(BuildContext, T) builder;
  final String emptyTitle;
  final Widget? alternative;

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const PageChromeBody(
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (error != null || data == null) {
      return PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.circleAlert,
          title: emptyTitle,
          message: error == null ? '' : '$error',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
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
    return builder(context, data!);
  }
}
