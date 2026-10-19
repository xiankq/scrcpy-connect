import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// A recovery status inside the page flow, leaving content and cleanup usable.
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
      await ref
          .read(appControllerProvider.notifier)
          .execute(InteropCommand.stateReconcile);
    } catch (_) {
      // The Bridge publishes the authoritative failure while keeping the gate.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (pending, error) = ref.watch(
      appControllerProvider.select(
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
