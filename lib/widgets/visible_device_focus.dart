import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Gives a verified device page focus only while its route is interactive.
/// Remote surfaces retain their stricter session ownership checks instead.
class VisibleDeviceFocus extends ConsumerStatefulWidget {
  const VisibleDeviceFocus({
    super.key,
    required this.controller,
    required this.deviceId,
    required this.child,
  });

  final AppController controller;
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
    final recovery = appControllerProvider.select(
      (state) => state.reconciliationPending,
    );
    // Preserve a resync marker even when its successful receipt arrives before
    // the next frame: the same visible device must then rearm audio follow.
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
        // No equality shortcut: resync clears the controller's audio follow
        // intent independently of the retained public focusedDeviceId.
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
