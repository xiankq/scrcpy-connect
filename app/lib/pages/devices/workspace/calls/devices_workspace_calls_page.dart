import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CallsPage extends HookWidget {
  const CallsPage({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final starting = useState(false);
    final openingCallUi = useState(false);
    final callUiFailure = useState<String?>(null);
    return PageFrame(
      title: '来电与通话',
      child: CommandView(
        controller: controller,
        command: 'calls.list',
        params: {'deviceId': device['id']},
        emptyTitle: '通话能力尚不可用',
        alternative: TextButton(
          onPressed: () =>
              openRemoteRoute(context, deviceId: value(device, 'id')),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data, refresh) {
          Future<void> verify() async {
            if (starting.value) return;
            starting.value = true;
            try {
              final result = await perform(
                context,
                controller,
                'observation.start',
                {'deviceId': device['id']},
              );
              if (context.mounted && result != null) refresh();
            } finally {
              if (context.mounted) starting.value = false;
            }
          }

          final calls = objects(data['calls']);
          final state = value(data, 'status', 'unknown');
          final verified =
              data['live'] == true &&
              (state == 'available' || state == 'limited');
          Future<void> openCurrentCallUi() async {
            if (openingCallUi.value) return;
            openingCallUi.value = true;
            callUiFailure.value = null;
            try {
              final result = await perform(context, controller, 'calls.open', {
                'deviceId': device['id'],
              });
              if (!context.mounted || result == null) return;
              if (result['acceptedBySystem'] != true ||
                  result['target'] != 'currentSystemCall') {
                callUiFailure.value = '手机尚未确认接受打开系统通话界面的请求。';
                return;
              }
              await openRemoteRoute(context, deviceId: value(device, 'id'));
            } finally {
              if (context.mounted) {
                openingCallUi.value = false;
                refresh();
              }
            }
          }

          final leading = <Widget>[
            ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('通话与声音', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    '通话控制：${statusText(value(data, 'controlStatus', value(data, 'status', 'unknown')))}',
                  ),
                  Text(
                    '主控双向语音：${statusText(value(data, 'audioStatus', 'unknown'))}',
                  ),
                  if (value(data, 'reason').isNotEmpty)
                    StateNote(value(data, 'reason')),
                  if (value(data, 'systemCallUiReason').isNotEmpty)
                    StateNote(value(data, 'systemCallUiReason')),
                  if (callUiFailure.value != null)
                    StateNote(callUiFailure.value!),
                  if (verified &&
                      calls.isNotEmpty &&
                      (data['canOpenSystemCallUi'] == true ||
                          data['canRetrySystemCallUi'] == true))
                    TextButton.icon(
                      onPressed: openingCallUi.value ? null : openCurrentCallUi,
                      icon: const Icon(LucideIcons.phone),
                      label: Text(
                        openingCallUi.value
                            ? '正在打开…'
                            : data['canRetrySystemCallUi'] == true
                            ? '重试打开系统通话界面'
                            : '打开系统通话界面',
                      ),
                    ),
                  Text(
                    value(data, 'audioRoute', '声音与麦克风继续由被控手机处理'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (calls.isEmpty)
              EmptyContent(
                icon: LucideIcons.phone,
                title: state == 'stopped'
                    ? '来电观察已停止'
                    : verified
                    ? '没有可控制的当前通话'
                    : '通话状态尚未核验',
                message: state == 'stopped'
                    ? '已停止同步此设备的通知与来电。需要时可主动启用观察。'
                    : verified
                    ? '主动拨号、联系人与通话记录请进入手机的原电话应用。'
                    : '尚未核实手机当前通话；启动观察后仍需等待实时状态。',
              ),
          ];
          final trailing = <Widget>[
            const SizedBox(height: DesignTokens.spacingLg),
            FilledButton.icon(
              onPressed: () =>
                  openRemoteRoute(context, deviceId: value(device, 'id')),
              icon: const Icon(
                LucideIcons.smartphone,
                size: DesignTokens.componentIconActionSize,
              ),
              label: const Text('在手机上继续处理'),
            ),
            TextButton(
              onPressed: starting.value ? null : verify,
              child: Text(state == 'stopped' ? '启用通知与来电观察' : '重新核验通话'),
            ),
            const StateNote('新的来电不会自动接听、抢占麦克风或结束已有通话。无法可靠针对某次呼叫操作时，请使用原手机界面。'),
          ];
          final indices = <Key, int>{
            for (var index = 0; index < calls.length; index++)
              ValueKey((
                'call',
                value(device, 'id'),
                value(calls[index], 'id'),
              )): leading.length + index,
          };
          return GroupedListView.builder(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            itemCount: leading.length + calls.length + trailing.length,
            findChildIndexCallback: (key) => indices[key],
            itemBuilder: (context, index) {
              if (index < leading.length) return leading[index];
              final row = index - leading.length;
              if (row >= calls.length) return trailing[row - calls.length];
              final call = calls[row];
              return Padding(
                key: ValueKey(('call', value(device, 'id'), value(call, 'id'))),
                padding: const EdgeInsets.only(top: DesignTokens.spacingLg),
                child: ContentPanel(
                  child: Column(
                    children: [
                      const FeatureIcon(
                        LucideIcons.userRound,
                        color: ConnectTokens.mint,

                        size: DesignTokens.componentEmptyContentIconSize,
                      ),
                      const SizedBox(height: DesignTokens.spacingMd),
                      Text(
                        value(call, 'name', value(call, 'number', '当前通话')),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(
                        '${value(call, 'deviceName', deviceName(device))} · ${statusText(value(call, 'state'))}',
                      ),
                      const SizedBox(height: DesignTokens.spacingLg),
                      Wrap(
                        spacing: DesignTokens.spacingMd,
                        runSpacing: DesignTokens.spacingSm,
                        alignment: WrapAlignment.center,
                        children: [
                          if (call['canAnswer'] == true)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: ConnectTokens.mint.withValues(
                                  alpha: .1,
                                ),
                              ),
                              onPressed: () async {
                                if (calls.any(
                                      (other) => other['state'] == 'active',
                                    ) &&
                                    !await confirm(
                                      context,
                                      '切换到这通来电？',
                                      '已有通话的麦克风和路由将按设备支持情况调整。不会自动结束其他通话。',
                                      action: '切换通话',
                                    )) {
                                  return;
                                }
                                if (context.mounted) {
                                  await perform(
                                    context,
                                    controller,
                                    'calls.action',
                                    {
                                      'deviceId': device['id'],
                                      'callId': call['id'],
                                      'action': 'answer',
                                    },
                                  );
                                  refresh();
                                }
                              },
                              icon: const Icon(
                                LucideIcons.phone,

                                size: DesignTokens.componentIconActionSize,
                              ),
                              label: const Text('接听'),
                            ),
                          if (call['canReject'] == true ||
                              call['canHangup'] == true)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                              onPressed: () async {
                                await perform(
                                  context,
                                  controller,
                                  'calls.action',
                                  {
                                    'deviceId': device['id'],
                                    'callId': call['id'],
                                    'action': call['canReject'] == true
                                        ? 'reject'
                                        : 'hangup',
                                  },
                                );
                                refresh();
                              },
                              icon: Icon(
                                LucideIcons.phoneOff,
                                color: Theme.of(context).colorScheme.error,
                                size: DesignTokens.componentIconActionSize,
                              ),
                              label: Text(
                                call['canReject'] == true ? '拒接' : '挂断',
                              ),
                            ),
                        ],
                      ),
                      if (call['canSetRoute'] == true)
                        TextButton(
                          onPressed: () async {
                            final routes = objects(call['routes']);
                            final route = await showGlassModalSheet<String>(
                              context: context,
                              builder: (context) => SafeArea(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: routes.length,
                                  itemBuilder: (context, index) {
                                    final route = routes[index];
                                    return ListTile(
                                      key: ValueKey((
                                        'call-route',
                                        value(route, 'id'),
                                      )),
                                      title: Text(value(route, 'name')),
                                      onTap: () => Navigator.pop(
                                        context,
                                        value(route, 'id'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                            if (route != null && context.mounted) {
                              await perform(
                                context,
                                controller,
                                'calls.action',
                                {
                                  'deviceId': device['id'],
                                  'callId': call['id'],
                                  'action': 'route',
                                  'route': route,
                                },
                              );
                              refresh();
                            }
                          },
                          child: const Text('声音路由'),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
