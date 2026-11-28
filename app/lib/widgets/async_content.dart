import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_loader.dart';

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
    this.failure = '请稍后重试。',
    this.alternative,
    this.loadingPlaceholder,
  });

  final bool loading;
  final T? data;
  final Object? error;
  final VoidCallback onRefresh;
  final Widget Function(BuildContext, T) builder;
  final String emptyTitle, failure;
  final Widget? alternative;
  final Widget? loadingPlaceholder;

  @override
  Widget build(BuildContext context) {
    final waiting = loading && data == null;
    return ContentArrival(
      state: waiting
          ? 'loading'
          : error != null || data == null
          ? 'unavailable'
          : 'ready',
      waiting: waiting,
      child: _content(context, waiting),
    );
  }

  Widget _content(BuildContext context, bool waiting) {
    if (waiting) {
      return loadingPlaceholder ?? const PageChromeBody(child: PageLoader());
    }
    if (error != null || data == null) {
      return PageChromeBody(
        child: EmptyContent(
          icon: LucideIcons.circleAlert,
          title: emptyTitle,
          message: error == null
              ? ''
              : failureMessage(error, fallback: failure),
          action: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignTokens.spacingSm,
            children: [
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(
                  AppIcons.refresh,
                  size: DesignTokens.componentBarGlyphSize,
                ),
                label: const Text('重试'),
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
