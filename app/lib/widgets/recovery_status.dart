import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 恢复状态位于正常页面内容流中，保留内容访问和清理操作。
class RecoveryStatus extends ConsumerStatefulWidget {
  const RecoveryStatus({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      DesignTokens.spacingMd,
      DesignTokens.spacingSm,
      DesignTokens.spacingMd,
      0,
    ),
  });
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<RecoveryStatus> createState() => _RecoveryStatusState();
}

class _RecoveryStatusState extends ConsumerState<RecoveryStatus> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await ref.read(reconcileStateProvider)();
    } catch (_) {
      // 桥接保持核验门禁，并发布权威失败状态。
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (pending, error) = ref.watch(
      recoveryStateProvider.select(
        (state) => (state.reconciliationPending, state.reconciliationError),
      ),
    );
    if (!pending) return const SizedBox.shrink();
    final failed = error != null;
    return Padding(
      padding: widget.padding,
      child: ContentPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingXs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: StateNote(
                  failed ? '暂时无法确认手机的连接状态。请重新检查。' : '正在检查手机的连接状态，请稍候。',
                  icon: failed ? LucideIcons.circleAlert : AppIcons.refresh,
                ),
              ),
            ),
            if (failed)
              OutlinedButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: const Icon(
                  AppIcons.refresh,
                  size: DesignTokens.componentIconActionSize,
                ),
                label: const Text('重新检查'),
              ),
          ],
        ),
      ),
    );
  }
}
