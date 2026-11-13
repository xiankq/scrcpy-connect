import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

/// 依次组装 regular 轨道、静止镜片和官方前景栏。
/// 栏通过 navigationBarSettings 保留手势、焦点和语义；指针手势期间由原移动镜片接管，不绘制额外边缘。
class NavigationSelectionLens extends StatefulWidget {
  const NavigationSelectionLens({
    super.key,
    required this.selectedIndex,
    required this.itemCount,
    required this.child,
  });

  final int selectedIndex;
  final int itemCount;
  final Widget child;

  @override
  State<NavigationSelectionLens> createState() =>
      _NavigationSelectionLensState();
}

class _NavigationSelectionLensState extends State<NavigationSelectionLens>
    with WidgetsBindingObserver {
  // 后端在 420 ms 按压窗口及对齐、厚度弹簧尾部保持移动镜片，其公开栏没有稳定回调。
  // 等待原镜片完成整个释放间隔后再显示静止镜片，避免释放期间两个光学面重叠；
  // 静止镜片本身始终保持在 Stack 中，避免卸载重挂载造成随机消失。
  static const _releaseInterval = Duration(milliseconds: 1100);
  final _pointers = <int>{};
  Timer? _settle;
  bool _interacting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _resetInteraction();
  }

  void _resetInteraction() {
    _settle?.cancel();
    if (_pointers.isEmpty && !_interacting) return;
    if (mounted) {
      setState(() {
        _pointers.clear();
        _interacting = false;
      });
    } else {
      _pointers.clear();
      _interacting = false;
    }
  }

  void _start(PointerDownEvent event) {
    if (!GlassMaterial.restingNavigationLens(context)) return;
    _settle?.cancel();
    _pointers.add(event.pointer);
    if (!_interacting) setState(() => _interacting = true);
  }

  void _end(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty || !_interacting) return;
    _settle?.cancel();
    _settle = Timer(_releaseInterval, () {
      if (mounted) setState(() => _interacting = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = GlassMaterial.restingNavigationLens(context);
    return Listener(
      onPointerDown: _start,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: liquid.AdaptiveGlass(
                  shape: const liquid.LiquidRoundedRectangle(
                    borderRadius: DesignTokens.componentNavigationRounded,
                  ),
                  settings: GlassMaterial.navigationTrackSettings(context),
                  quality: liquid.GlassQuality.premium,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          if (enabled)
            liquid.AnimatedGlassIndicator(
              key: const ValueKey('resting-navigation-lens'),
              velocity: 0,
              itemCount: widget.itemCount,
              alignment: AlignmentDirectional(
                widget.itemCount == 1
                    ? 0
                    : -1 + 2 * widget.selectedIndex / (widget.itemCount - 1),
                0,
              ),
              // Keep the Positioned returned by the library directly under
              // Stack. Zero thickness suppresses paint while the moving lens
              // owns the interaction, without mounting a second indicator.
              thickness: _interacting ? 0 : 1,
              quality: liquid.GlassQuality.premium,
              indicatorColor: DesignTokens.colorTransparent,
              isBackgroundIndicator: false,
              paintBackground: false,
              padding: const EdgeInsets.all(DesignTokens.spacingXxs),
              expansion: EdgeInsets.zero,
              pinchStrength: 0,
              settings: GlassMaterial.navigationLensSettings(context)
                  .copyWith(shadow: const []),
            ),
          widget.child,
        ],
      ),
    );
  }
}
