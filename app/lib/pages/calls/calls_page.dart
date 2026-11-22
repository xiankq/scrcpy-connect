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
    return Theme(
      data: ConnectTokens.theme(
        Brightness.dark,
        fontFamily: appText?.fontFamily,
        fontFamilyFallback: appText?.fontFamilyFallback,
      ),
      child: PageFrame(
        title: '电话',
        backgroundColor: DesignTokens.colorCallStage,
        child: AsyncContent(
          loading: result.isLoading,
          data: result.asData?.value,
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
                    failureMessage(error, fallback: '无法打开来电界面。请直接在手机上处理。'),
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
            final action = current == null ? openPhoneApp : openCurrentCallUi;
            final canOpen =
                current == null ||
                data.canOpenSystemCallUi ||
                data.canRetrySystemCallUi;
            final text = Theme.of(context).textTheme;
            return PageChromeBody(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '来自 ${deviceName(device)}',
                            style: text.labelLarge?.copyWith(
                              color: DesignTokens.colorCallMuted,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingLg),
                          _CallOrbit(
                            ringing: ringing,
                            child: Padding(
                              padding: const EdgeInsets.all(
                                DesignTokens.spacingXs,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: DesignTokens.colorCallRing
                                        .withValues(alpha: ringing ? 1 : .5),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    DesignTokens.spacingMd,
                                  ),
                                  child: SizedBox.square(
                                    dimension:
                                        DesignTokens.componentCallAvatarSize,
                                    child: CircleAvatar(
                                      backgroundColor:
                                          DesignTokens.colorCallAvatar,
                                      foregroundColor:
                                          DesignTokens.colorCallStage,
                                      child: caller == null
                                          ? Icon(
                                              current == null
                                                  ? LucideIcons.phone
                                                  : LucideIcons.user,
                                              size: DesignTokens
                                                  .componentIconLargeSize,
                                            )
                                          : Text(
                                              caller.characters.firstOrNull ??
                                                  '·',
                                              style: text.displaySmall
                                                  ?.copyWith(
                                                    color: DesignTokens
                                                        .colorCallStage,
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingLg),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              caller ?? (current == null ? phase : '来电者未知'),
                              textAlign: TextAlign.center,
                              style: text.headlineLarge?.copyWith(
                                color: DesignTokens.colorWhite,
                              ),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingXs),
                          if (current != null)
                            Text(
                              phase,
                              style: text.titleMedium?.copyWith(
                                color: DesignTokens.colorCallMuted,
                              ),
                            ),
                          const SizedBox(height: DesignTokens.spacingLg),
                          Material(
                            color: DesignTokens.colorCallDock,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.componentCallDockRounded,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(
                                DesignTokens.spacingMd,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (current != null || !verified)
                                    Text(
                                      current != null
                                          ? '声音仍在手机'
                                          : '暂时无法读取来电状态。请直接在手机上查看。',
                                      style: text.bodySmall?.copyWith(
                                        color: DesignTokens.colorCallMuted,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (operation.value.failure
                                      case final message?)
                                    Text(
                                      message,
                                      style: text.bodyMedium?.copyWith(
                                        color: DesignTokens.colorWhite,
                                      ),
                                    ),
                                  const SizedBox(
                                    height: DesignTokens.spacingSm,
                                  ),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          DesignTokens.colorCallKey,
                                      foregroundColor: DesignTokens.colorWhite,
                                    ),
                                    onPressed:
                                        operation.value.opening || !canOpen
                                        ? null
                                        : action,
                                    icon: Icon(
                                      ringing
                                          ? LucideIcons.phoneIncoming
                                          : LucideIcons.phone,
                                    ),
                                    label: Text(
                                      operation.value.opening
                                          ? '正在打开…'
                                          : current == null
                                          ? '打开手机电话'
                                          : ringing
                                          ? '在手机画面接听'
                                          : '打开手机通话界面',
                                    ),
                                  ),
                                  if (!verified)
                                    TextButton(
                                      onPressed: starting.value ? null : verify,
                                      child: Text(
                                        state == .stopped ? '启用来电观察' : '检查通话状态',
                                        style: text.labelLarge?.copyWith(
                                          color: DesignTokens.colorWhite,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CallOrbit extends HookWidget {
  const _CallOrbit({required this.ringing, required this.child});

  final bool ringing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lifecycle = useAppLifecycleState();
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
    return AnimatedBuilder(
      animation: pulse,
      child: child,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: DesignTokens.colorCallRing.withValues(
              alpha: active
                  ? .42 + panelCurve.transform(pulse.value) * .5
                  : .45,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
