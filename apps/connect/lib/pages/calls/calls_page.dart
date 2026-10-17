import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CallsPage extends HookConsumerWidget {
  const CallsPage({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    return PageFrame(
      title: '来电与通话',
      subtitle: deviceName(device),
      child: CommandView(
        refreshKey: appEventRevision,
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
          final calls = objects(data['calls']);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '通话与声音',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '通话控制：${statusText(value(data, 'controlStatus', value(data, 'status', 'unknown')))}',
                    ),
                    Text(
                      '主控双向语音：${statusText(value(data, 'audioStatus', 'unknown'))}',
                    ),
                    if (value(data, 'reason').isNotEmpty)
                      StateNote(value(data, 'reason')),
                    Text(
                      value(data, 'audioRoute', '声音与麦克风继续由被控手机处理'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (calls.isEmpty)
                const EmptyContent(
                  icon: LucideIcons.phone,
                  title: '没有可控制的当前通话',
                  message: '主动拨号、联系人与通话记录请进入手机的原电话应用。',
                ),
              for (final call in calls)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ContentPanel(
                    child: Column(
                      children: [
                        const FeatureIcon(
                          LucideIcons.userRound,
                          color: ConnectTokens.mint,
                          size: 80,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          value(call, 'name', value(call, 'number', '当前通话')),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${value(call, 'deviceName', deviceName(device))} · ${value(call, 'state')}',
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            if (call['canAnswer'] == true)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: ConnectTokens.mint
                                      .withValues(alpha: .1),
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
                                  color: ConnectTokens.mint,
                                  size: 18,
                                ),
                                label: const Text('接听'),
                              ),
                            if (call['canReject'] == true ||
                                call['canHangup'] == true)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: ConnectTokens.danger,
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
                                icon: const Icon(
                                  LucideIcons.phoneOff,
                                  size: 18,
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
                              final route = await showModalBottomSheet<String>(
                                context: context,
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final route in objects(
                                        call['routes'],
                                      ))
                                        ListTile(
                                          title: Text(value(route, 'name')),
                                          onTap: () => Navigator.pop(
                                            context,
                                            value(route, 'id'),
                                          ),
                                        ),
                                    ],
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
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    openRemoteRoute(context, deviceId: value(device, 'id')),
                icon: const Icon(LucideIcons.smartphone, size: 18),
                label: const Text('在手机上继续处理'),
              ),
              TextButton(
                onPressed: () async {
                  final result = await perform(
                    context,
                    controller,
                    'calls.list',
                    {'deviceId': device['id'], 'allowStart': true},
                  );
                  if (context.mounted && result != null) refresh();
                },
                child: const Text('刷新通话状态'),
              ),
              const StateNote(
                '新的来电不会自动接听、抢占麦克风或结束已有通话。无法可靠针对某次呼叫操作时，请使用原手机界面。',
              ),
            ],
          );
        },
      ),
    );
  }
}
