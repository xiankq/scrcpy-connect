import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/call_stage_background.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/soft_glow.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class CallsPage extends HookConsumerWidget {
  const CallsPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observation = ref.watch(deviceObservationProvider);
    final starting = useValueNotifier(false, [observation, device.id]);
    useListenable(starting);
    final currentStarting = useRef(starting);
    currentStarting.value = starting;
    bool observationCurrent() =>
        context.mounted &&
        identical(currentStarting.value, starting) &&
        identical(observation, ref.read(deviceObservationProvider));
    final callAccess = ref.watch(deviceCallsProvider);
    final provider = deviceCallsSnapshotProvider(device.id);
    final result = ref.watch(provider);
    void refresh() => ref.invalidate(provider);
    final operation = useValueNotifier(
      (opening: false, failure: null as String?),
      [callAccess, device.id],
    );
    useListenable(operation);
    final currentOperation = useRef(operation);
    currentOperation.value = operation;
    bool actionCurrent() =>
        context.mounted &&
        identical(currentOperation.value, operation) &&
        identical(callAccess, ref.read(deviceCallsProvider));

    Future<void> requestUi({required bool currentSystemCall}) async {
      if (operation.value.opening) return;
      operation.value = (opening: true, failure: null);
      try {
        if (currentSystemCall) {
          await callAccess.requestCurrentCallUi(device.id);
        } else {
          await callAccess.requestPhoneApp(device.id);
        }
        if (!context.mounted || !actionCurrent()) return;
        await openRemoteRoute(context, deviceId: device.id);
      } catch (error) {
        if (context.mounted && actionCurrent()) {
          if (error case RequestFailure(
            code: 'call_ui_unconfirmed',
            :final message,
          )) {
            operation.value = (opening: true, failure: message);
          } else {
            feedback(
              context,
              failureMessage(error, fallback: '暂时无法确认操作是否生效。请先查看手机上的来电状态。'),
            );
          }
        }
      } finally {
        if (actionCurrent()) {
          operation.value = (opening: false, failure: operation.value.failure);
          if (currentSystemCall) refresh();
        }
      }
    }

    Future<void> openPhoneApp() => requestUi(currentSystemCall: false);
    Future<void> openCurrentCallUi() => requestUi(currentSystemCall: true);

    final appText = Theme.of(context).textTheme.bodyMedium;
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    return Theme(
      data: ConnectTokens.theme(
        Brightness.dark,
        fontFamily: appText?.fontFamily,
        fontFamilyFallback: appText?.fontFamilyFallback,
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CallStageBackground()),
          Builder(
            builder: (context) {
              Widget frame({required String source, required Widget child}) =>
                  PageFrame(
                    title: '电话',
                    backgroundColor: DesignTokens.colorCallStage.withAlpha(0),
                    // 舞台上的返回键为 glass-clear（Ardot C4 37:1804），来源胶囊居中。
                    leading: Tooltip(
                      message: backLabel,
                      excludeFromSemantics: true,
                      child: GlassToolbarIconButton(
                        variant: GlassVariant.clear,
                        semanticLabel: backLabel,
                        onPressed: () => closePage<void>(context),
                        icon: const Icon(AppIcons.back),
                      ),
                    ),
                    titleContent: Semantics(
                      header: true,
                      label: '电话',
                      child: _SourceCapsule(text: source),
                    ),
                    child: child,
                  );
              final name = deviceName(device);
              final snapshot = result.asData?.value;
              final headerCall = snapshot?.verified == true
                  ? snapshot!.calls.firstOrNull
                  : null;
              return frame(
                source: headerCall == null
                    ? name
                    : headerCall.state == .ringing
                    ? '$name · 铃声在手机'
                    : '$name · 声音仍在手机',
                child: AsyncContent(
                  loading: result.isLoading,
                  data: snapshot,
                  error: result.error,
                  onRefresh: refresh,
                  emptyTitle: '暂时无法读取通话状态',
                  failure: '请检查手机连接，或直接在手机上查看。',
                  alternative: TextButton(
                    onPressed: operation.value.opening ? null : openPhoneApp,
                    child: const Text('打开手机电话界面'),
                  ),
                  builder: (context, data) {
                    final state = data.status;
                    final verified = data.verified;
                    final calls = verified ? data.calls : const <DeviceCall>[];
                    Future<void> verify() async {
                      if (starting.value) return;
                      starting.value = true;
                      try {
                        await observation.startObservation(device.id);
                        if (observationCurrent()) refresh();
                      } catch (error) {
                        if (context.mounted && observationCurrent()) {
                          feedback(
                            context,
                            failureMessage(
                              error,
                              fallback: '无法打开来电界面。请直接在手机上处理。',
                            ),
                          );
                        }
                      } finally {
                        if (observationCurrent()) starting.value = false;
                      }
                    }

                    final current = calls.firstOrNull;
                    final caller = current?.aggregate == false
                        ? current?.name ?? current?.number
                        : null;
                    final ringing = current?.state == .ringing;
                    final phase = current != null
                        ? statusText(current.state.name)
                        : state == .stopped
                        ? '来电观察已停止'
                        : verified
                        ? '当前没有通话'
                        : '暂时无法读取通话状态';
                    final action = current == null
                        ? openPhoneApp
                        : openCurrentCallUi;
                    final canOpen =
                        current == null ||
                        data.canOpenSystemCallUi ||
                        data.canRetrySystemCallUi;
                    final failure = operation.value.failure;
                    final actionLabel = operation.value.opening
                        ? '正在打开…'
                        : current == null
                        ? '打开手机电话'
                        : ringing
                        ? '在手机画面接听'
                        : '打开手机通话界面';
                    final onAction = operation.value.opening || !canOpen
                        ? null
                        : action;
                    final text = AppTypography.of(context);
                    final note = text.subheadline.copyWith(
                      color: DesignTokens.colorCallTextSecondary,
                    );
                    // 有通话时动作区是 glass-clear 胶囊（C4 37:1778）；没有通话或画面待核对时
                    // 打开手机电话是本屏唯一主动作（C7 37:2055）。
                    final openAction = current != null && failure == null
                        ? AppButton(
                            role: AppButtonRole.glass,
                            expand: true,
                            label: actionLabel,
                            icon: LucideIcons.smartphone,
                            onPressed: onAction,
                          )
                        : _StagePrimaryButton(
                            label: actionLabel,
                            icon: LucideIcons.smartphone,
                            onPressed: onAction,
                          );
                    final actions = verified
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: DesignTokens.spacingXxl,
                            children: [
                              if (failure != null)
                                Text(
                                  failure,
                                  textAlign: TextAlign.center,
                                  style: note,
                                ),
                              openAction,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: DesignTokens.spacingMd,
                            children: [
                              AppButton(
                                role: AppButtonRole.glass,
                                expand: true,
                                label: actionLabel,
                                icon: LucideIcons.smartphone,
                                onPressed: onAction,
                              ),
                              // 读取中断时的动作托盘（C6 37:2049）：说明 + 唯一主动作。
                              Glass(
                                variant: GlassVariant.clear,
                                radius: DesignTokens.roundedAlert,
                                showShadow: false,
                                padding: const EdgeInsets.fromLTRB(
                                  DesignTokens.spacingLg,
                                  DesignTokens.spacingXl,
                                  DesignTokens.spacingLg,
                                  DesignTokens.spacingLg,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: DesignTokens.spacingLg,
                                  children: [
                                    Text(
                                      '暂时无法读取来电状态。请直接在手机上查看。',
                                      textAlign: TextAlign.center,
                                      style: text.subheadline.copyWith(
                                        color: DesignTokens.colorOnMedia,
                                      ),
                                    ),
                                    if (failure != null)
                                      Text(
                                        failure,
                                        textAlign: TextAlign.center,
                                        style: note,
                                      ),
                                    _StagePrimaryButton(
                                      label: state == .stopped
                                          ? '启用来电观察'
                                          : '检查通话状态',
                                      icon: AppIcons.refresh,
                                      onPressed: starting.value ? null : verify,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                    final look = !verified
                        ? _CallerLook.interrupted
                        : failure != null
                        ? _CallerLook.unconfirmed
                        : ringing
                        ? _CallerLook.ringing
                        : current != null
                        ? _CallerLook.inCall
                        : _CallerLook.idle;
                    final headline = [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          caller ?? (current == null ? phase : '来电者未知'),
                          textAlign: TextAlign.center,
                          style: text.largeTitle.copyWith(
                            color: DesignTokens.colorOnMedia,
                          ),
                        ),
                      ),
                      if (current != null) ...[
                        const SizedBox(height: DesignTokens.spacingXs),
                        Text(
                          phase,
                          textAlign: TextAlign.center,
                          style: text.body.copyWith(
                            color: DesignTokens.colorOnMedia.withValues(
                              alpha: _stageLineOpacity,
                            ),
                          ),
                        ),
                      ],
                      if (current?.state == .active) ...[
                        const SizedBox(height: DesignTokens.spacingSm),
                        const _Waveform(),
                      ],
                    ];
                    return PageChromeBody(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              constraints.maxHeight < _compactHeight;
                          final visual = _CallerVisual(
                            compact: compact,
                            look: look,
                            avatar: _Avatar(
                              size: current == null
                                  ? _idleAvatarSize
                                  : _avatarSize,
                              initial: caller?.characters.firstOrNull,
                              icon: current == null
                                  ? AppIcons.calls
                                  : LucideIcons.user,
                              contact: current != null,
                            ),
                          );
                          const padding = EdgeInsets.fromLTRB(
                            DesignTokens.spacingLg,
                            DesignTokens.spacingLg,
                            DesignTokens.spacingLg,
                            DesignTokens.spacingSm,
                          );
                          // 矮而宽的窗口：头像位在起始侧，姓名与动作在另一侧。
                          if (compact &&
                              constraints.maxWidth > constraints.maxHeight) {
                            return SingleChildScrollView(
                              padding: padding,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                spacing: DesignTokens.spacingXxl,
                                children: [
                                  visual,
                                  Flexible(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: _contentMaxWidth,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          ...headline,
                                          const SizedBox(
                                            height: DesignTokens.spacingXxl,
                                          ),
                                          actions,
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return CustomScrollView(
                            slivers: [
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: _contentMaxWidth,
                                    ),
                                    child: Padding(
                                      padding: padding,
                                      child: Column(
                                        children: [
                                          visual,
                                          const SizedBox(
                                            height: DesignTokens.spacingSm,
                                          ),
                                          ...headline,
                                          const Spacer(),
                                          const SizedBox(
                                            height: DesignTokens.spacingXxxl,
                                          ),
                                          actions,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 来源胶囊（Ardot C4 44:18）：glass-clear，高 32，内距 10/12，图形 16 与文字间距 6。
class _SourceCapsule extends StatelessWidget {
  const _SourceCapsule({required this.text});

  final String text;

  static const _height = 32.0;
  static const _glyph = 16.0;
  static const _gap = 6.0;
  static const _padding = EdgeInsetsDirectional.fromSTEB(10, 0, 12, 0);

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    return Glass(
      variant: GlassVariant.clear,
      radius: DesignTokens.roundedFull,
      showShadow: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _height),
        child: Padding(
          padding: _padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: _gap,
            children: [
              const Icon(
                LucideIcons.smartphone,
                size: _glyph,
                color: DesignTokens.colorOnMedia,
              ),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.footnote.copyWith(
                    color: DesignTokens.colorOnMedia,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CallerLook { ringing, inCall, interrupted, unconfirmed, idle }

/// 头像位：响铃为 256/208/160 三道同心环（C4 37:1766），通话中为身后主色光晕（C5 44:22），
/// 读取中断为变暗头像与琥珀徽标（C6 44:37），画面待核对为 160 虚线环（C7 44:91）。
class _CallerVisual extends HookWidget {
  const _CallerVisual({
    required this.look,
    required this.avatar,
    required this.compact,
  });

  final _CallerLook look;
  final Widget avatar;

  /// 矮窗只保留 208 头像位，响铃外环收进来。
  final bool compact;

  static const _ringSizes = [256.0, 208.0, 160.0];
  static const _ringOpacity = [.14, .22, .32];
  static const _slot = 208.0;
  static const _glowBlur = 48.0;
  static const _glowSize = 160.0;
  static const _glowOpacity = .7;
  static const _badgeSize = 36.0;
  static const _badgeGlyph = 20.0;
  static const _badgeBorder = 2.0;
  static const _dimmed = .6;

  @override
  Widget build(BuildContext context) {
    final lifecycle = useAppLifecycleState();
    final ringing = look == _CallerLook.ringing;
    final active =
        ringing &&
        !reduceMotionOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.isCurrentOf(context) != false &&
        TickerMode.valuesOf(context).enabled;
    final pulse = useAnimationController(
      duration: const Duration(milliseconds: 1800),
    );
    useEffect(() {
      if (active) {
        pulse.repeat(reverse: true);
      } else {
        pulse.stop();
      }
      return null;
    }, [active, pulse]);
    final rings = compact ? _ringSizes.skip(1) : _ringSizes;
    final dimension = ringing && !compact ? _ringSizes.first : _slot;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: dimension,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (ringing)
              for (final (index, size) in rings.indexed)
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) => SizedBox.square(
                    dimension: size,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: DesignTokens.colorOnMedia.withValues(
                            alpha:
                                _ringOpacity[index + (compact ? 1 : 0)] *
                                (active
                                    ? .55 +
                                          .45 *
                                              panelCurve.transform(pulse.value)
                                    : 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            if (look == _CallerLook.inCall)
              SizedBox.square(
                dimension: _glowSize + 2 * _glowBlur,
                child: SoftGlow(
                  color: DesignTokens.colorPrimary.withValues(
                    alpha: _glowOpacity,
                  ),
                  blur: _glowBlur,
                ),
              ),
            if (look == _CallerLook.unconfirmed)
              const SizedBox.square(
                dimension: _glowSize,
                child: CustomPaint(painter: _DashedRingPainter()),
              ),
            if (look == _CallerLook.interrupted)
              Opacity(opacity: _dimmed, child: avatar)
            else
              avatar,
            if (look == _CallerLook.interrupted)
              Positioned(
                left: _slot / 2 + _avatarSize / 2 - _badgeSize + _badgeBorder,
                top: _slot / 2 + _avatarSize / 2 - _badgeSize + _badgeBorder,
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DesignTokens.colorAccentAmber,
                    border: Border.all(
                      color: DesignTokens.colorCallStage,
                      width: _badgeBorder,
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.unplug,
                    size: _badgeGlyph,
                    color: DesignTokens.colorOnMedia,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 头像：联系人为 `primary-container` 底与首字或人形；没有通话时为 `call-key` 底与电话图形。
/// 描边白色 2（C4 37:1769）。
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.size,
    required this.initial,
    required this.icon,
    required this.contact,
  });

  final double size;
  final String? initial;
  final IconData icon;
  final bool contact;

  /// 首字 48/56 Bold（C4 37:1770），图形 40（C7 37:2052）。
  static const _initialSize = 48.0;
  static const _glyph = 40.0;
  static const _ring = 2.0;

  @override
  Widget build(BuildContext context) {
    final foreground = contact
        ? DesignTokens.colorOnPrimaryContainer
        : DesignTokens.colorOnMedia;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: contact
            ? DesignTokens.colorPrimaryContainer
            : DesignTokens.colorCallKey,
        border: Border.all(color: DesignTokens.colorOnMedia, width: _ring),
      ),
      child: initial == null
          ? Icon(icon, size: _glyph, color: foreground)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                initial!,
                style: AppTypography.of(context).largeTitle
                    .copyWith(fontSize: _initialSize, color: foreground),
              ),
            ),
    );
  }
}

/// 画面待核对的 160 虚线环（C7 44:91），白色 32%。
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  static const _dashes = 48;
  static const _dashShare = .5;
  static const _opacity = .32;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = DesignTokens.spacingHairline
      ..color = DesignTokens.colorOnMedia.withValues(alpha: _opacity);
    const sweep = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(
        rect.deflate(.5),
        i * sweep,
        sweep * _dashShare,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) => false;
}

/// 通话中的声波装饰（C5 44:23）：9 根宽 3、间距 4 的白色圆角条，静态。
class _Waveform extends StatelessWidget {
  const _Waveform();

  static const _heights = [8.0, 14.0, 22.0, 12.0, 26.0, 16.0, 10.0, 18.0, 8.0];
  static const _barWidth = 3.0;
  static const _height = 28.0;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignTokens.spacingXs,
        children: [
          for (final height in _heights)
            Container(
              width: _barWidth,
              height: height,
              decoration: const ShapeDecoration(
                color: DesignTokens.colorOnMedia,
                shape: StadiumBorder(),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 舞台上的主动作：与 `primary` 按钮同几何，底色与文字固定为舞台上的亮色主色与白字（C7 37:2055）。
class _StagePrimaryButton extends StatelessWidget {
  const _StagePrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = AppButton.styleOf(context, role: AppButtonRole.primary);
    WidgetStateProperty<Color?> enabled(Color color) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : states.contains(WidgetState.pressed)
              ? Color.alphaBlend(_pressedOverlay, color)
              : color,
        );
    WidgetStateProperty<Color?> merge(
      WidgetStateProperty<Color?>? base,
      WidgetStateProperty<Color?> override,
    ) => WidgetStateProperty.resolveWith(
      (states) => override.resolve(states) ?? base?.resolve(states),
    );
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: style.copyWith(
          backgroundColor: merge(
            style.backgroundColor,
            enabled(DesignTokens.colorPrimary),
          ),
          foregroundColor: merge(
            style.foregroundColor,
            WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? null
                  : DesignTokens.colorOnPrimary,
            ),
          ),
          iconColor: merge(
            style.iconColor,
            WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? null
                  : DesignTokens.colorOnPrimary,
            ),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  /// 深色面上按下叠加 20% 白（interaction-motion「触点反馈」）。
  static final _pressedOverlay = DesignTokens.colorOnMedia.withValues(
    alpha: .2,
  );
}

/// 来电头像 120（C4 37:1769），没有通话时的电话图形头像 112（C7 37:1970）。
const _avatarSize = 120.0;
const _idleAvatarSize = 112.0;

/// 阶段文字为白色 72%（C4 37:1772）。
const _stageLineOpacity = .72;

/// 通话舞台内容最宽 400，宽窗居中（画板 402 宽）。
const _contentMaxWidth = 400.0;

/// 低于此高度时响铃环收到 208，避免横屏把动作挤出首屏。
const _compactHeight = 600.0;
