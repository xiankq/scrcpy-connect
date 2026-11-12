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
    final reason = error?.trim();
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
                  failed
                      ? '当前状态尚待核验：${reason == null || reason.isEmpty ? '暂未能完成检查，请重试。' : reason}'
                      : '正在核验设备与活动状态，完成前暂缓新的操作。',
                  icon: failed
                      ? LucideIcons.circleAlert
                      : LucideIcons.refreshCw,
                ),
              ),
            ),
            if (failed)
              OutlinedButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: const Icon(
                  LucideIcons.refreshCw,
                  size: DesignTokens.componentIconActionSize,
                ),
                label: const Text('重新核验'),
              ),
          ],
        ),
      ),
    );
  }
}
