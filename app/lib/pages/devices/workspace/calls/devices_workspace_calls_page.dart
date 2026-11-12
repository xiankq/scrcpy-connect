import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class CallsPage extends HookConsumerWidget {
  const CallsPage({super.key, required this.controller, required this.device});
  final AppNotifier controller;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observation = ref.watch(
      appDependenciesProvider.select((source) => source.observation),
    );
    final starting = useValueNotifier(false, [observation, device.id]);
    useListenable(starting);
    final currentStarting = useRef(starting);
    currentStarting.value = starting;
    bool observationCurrent() =>
        context.mounted &&
        identical(currentStarting.value, starting) &&
        identical(observation, controller.observation);
    final callAccess = ref.watch(
      appDependenciesProvider.select((source) => source.calls),
    );
    final provider = deviceCallsProvider(device.id);
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
        identical(callAccess, controller.calls);

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
            feedback(context, '$error');
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

    return PageFrame(
      title: '电话',
      child: AsyncContent(
        loading: result.isLoading,
        data: result.asData?.value,
        error: result.error,
        onRefresh: refresh,
        emptyTitle: '通话状态尚未核验',
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
                feedback(context, '$error');
              }
            } finally {
              if (observationCurrent()) starting.value = false;
            }
          }

          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              StateNote(deviceName(device), icon: LucideIcons.smartphone),
              ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FeatureIcon(
                      LucideIcons.phone,
                      color: ConnectTokens.mint,
                      size: DesignTokens.componentEmptyContentIconSize,
                    ),
                    const SizedBox(height: DesignTokens.spacingLg),
                    if (calls.isEmpty) ...[
                      Text(
                        state == DeviceCallAvailability.stopped
                            ? '来电观察已停止'
                            : verified
                            ? '当前没有通话'
                            : '通话状态尚未核验',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      const Text('可在手机原电话应用中接听、拨号、查找联系人和通话记录。'),
                    ] else
                      for (final call in calls) ...[
                        Text(
                          call.aggregate
                              ? '来电者未知'
                              : call.name ?? call.number ?? '来电者未知',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          statusText(call.state.name),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: DesignTokens.spacingSm),
                      ],
                    const SizedBox(height: DesignTokens.spacingMd),
                    const Text('声音仍在手机'),
                    if (!verified && (data.reason?.isNotEmpty ?? false))
                      StateNote(data.reason!),
                    if (calls.isNotEmpty) const Text('请在手机画面中接听或挂断。'),
                    if (operation.value.failure != null)
                      StateNote(operation.value.failure!),
                    if (calls.isEmpty) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
                      FilledButton.icon(
                        onPressed: operation.value.opening
                            ? null
                            : openPhoneApp,
                        icon: const Icon(LucideIcons.phone),
                        label: Text(
                          operation.value.opening ? '正在打开…' : '打开手机电话界面',
                        ),
                      ),
                    ],
                    if (verified &&
                        calls.isNotEmpty &&
                        (data.canOpenSystemCallUi ||
                            data.canRetrySystemCallUi)) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
                      FilledButton.icon(
                        onPressed: operation.value.opening
                            ? null
                            : openCurrentCallUi,
                        icon: const Icon(LucideIcons.phone),
                        label: Text(
                          operation.value.opening
                              ? '正在打开…'
                              : data.canRetrySystemCallUi
                              ? '重试打开系统通话界面'
                              : calls.any(
                                  (call) =>
                                      call.state == DeviceCallState.ringing,
                                )
                              ? '在手机画面接听'
                              : '打开手机通话界面',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              OutlinedButton.icon(
                onPressed: () => openRemoteRoute(context, deviceId: device.id),
                icon: const Icon(LucideIcons.smartphone),
                label: const Text('打开手机屏幕'),
              ),
              TextButton(
                onPressed: () =>
                    AppsRoute(deviceId: device.id).push<void>(context),
                child: const Text('从全部应用打开电话'),
              ),
              TextButton(
                onPressed: starting.value ? null : verify,
                child: Text(
                  state == DeviceCallAvailability.stopped
                      ? '启用通知与来电观察'
                      : '重新核验通话',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
