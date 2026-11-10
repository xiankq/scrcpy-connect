import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

/// 只有已核验且可交互的设备页面能取得焦点；远控画面另行核对会话所有权。
class VisibleDeviceFocus extends ConsumerStatefulWidget {
  const VisibleDeviceFocus({
    super.key,
    required this.controller,
    required this.deviceId,
    required this.child,
  });

  final AppStore controller;
  final String deviceId;
  final Widget child;

  @override
  ConsumerState<VisibleDeviceFocus> createState() => _VisibleDeviceFocusState();
}

class _VisibleDeviceFocusState extends ConsumerState<VisibleDeviceFocus>
    with WidgetsBindingObserver {
  bool _active = false;
  int _epoch = 0;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _invalidate() {
    _active = false;
    _epoch++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(VisibleDeviceFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.deviceId != widget.deviceId) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _invalidate();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recovery = appStoreProvider.select(
      (state) => state.reconciliationPending,
    );
    // 即使重同步在下一帧前完成，也要保留核验标记，使同一可见设备重新激活剪贴板。
    ref.listen(recovery, (_, pending) {
      if (pending) _invalidate();
    });
    final pending = ref.watch(recovery);
    final current = ModalRoute.isCurrentOf(context) == true;
    if (!current || pending || !_foreground || widget.deviceId.isEmpty) {
      _invalidate();
    } else if (!_active) {
      _active = true;
      final epoch = ++_epoch;
      final controller = widget.controller;
      final deviceId = widget.deviceId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_active ||
            epoch != _epoch ||
            controller.isDisposed() ||
            controller.snapshot().reconciliationPending ||
            !_foreground ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        // 核验后重新声明可见设备，即使公开焦点仍指向同一设备。
        unawaited(controller.focusDevice(deviceId));
      });
    }
    return widget.child;
  }

  @override
  void dispose() {
    _invalidate();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
