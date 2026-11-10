import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class CallsPage extends HookWidget {
  const CallsPage({super.key, required this.controller, required this.device});
  final AppStore controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final starting = useState(false);
    final opening = useState(false);
    final failure = useState<String?>(null);
    Future<void> openPhoneApp() async {
      if (opening.value) return;
      opening.value = true;
      failure.value = null;
      try {
        final result = await perform(
          context,
          controller,
          'calls.openPhoneApp',
          {'deviceId': device['id']},
        );
        if (!context.mounted || result == null) return;
        if (result['acceptedBySystem'] != true ||
            result['target'] != 'phoneApp') {
          failure.value = '手机尚未确认接受打开电话应用的请求。';
          return;
        }
        await openRemoteRoute(context, deviceId: value(device, 'id'));
      } finally {
        if (context.mounted) opening.value = false;
      }
    }

    return PageFrame(
      title: '电话',
      child: CommandView(
        controller: controller,
        command: 'calls.list',
        params: {'deviceId': device['id']},
        emptyTitle: '通话状态尚未核验',
        alternative: TextButton(
          onPressed: opening.value ? null : openPhoneApp,
          child: const Text('打开手机电话界面'),
        ),
        builder: (context, data, refresh) {
          final state = value(data, 'status', 'unknown');
          final verified =
              data['live'] == true && ['available', 'limited'].contains(state);
          final calls = verified ? objects(data['calls']) : <Json>[];
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

          Future<void> openCurrentCallUi() async {
            if (opening.value) return;
            opening.value = true;
            failure.value = null;
            try {
              final result = await perform(context, controller, 'calls.open', {
                'deviceId': device['id'],
              });
              if (!context.mounted || result == null) return;
              if (result['acceptedBySystem'] != true ||
                  result['target'] != 'currentSystemCall') {
                failure.value = '手机尚未确认接受打开系统通话界面的请求。';
                return;
              }
              await openRemoteRoute(context, deviceId: value(device, 'id'));
            } finally {
              if (context.mounted) {
                opening.value = false;
                refresh();
              }
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
                        state == 'stopped'
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
                          call['aggregate'] == true
                              ? '来电者未知'
                              : value(
                                  call,
                                  'name',
                                  value(call, 'number', '来电者未知'),
                                ),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          statusText(value(call, 'state')),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: DesignTokens.spacingSm),
                      ],
                    const SizedBox(height: DesignTokens.spacingMd),
                    const Text('声音仍在手机'),
                    if (!verified && value(data, 'reason').isNotEmpty)
                      StateNote(value(data, 'reason')),
                    if (calls.isNotEmpty) const Text('请在手机画面中接听或挂断。'),
                    if (failure.value != null) StateNote(failure.value!),
                    if (calls.isEmpty) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
                      FilledButton.icon(
                        onPressed: opening.value ? null : openPhoneApp,
                        icon: const Icon(LucideIcons.phone),
                        label: Text(opening.value ? '正在打开…' : '打开手机电话界面'),
                      ),
                    ],
                    if (verified &&
                        calls.isNotEmpty &&
                        (data['canOpenSystemCallUi'] == true ||
                            data['canRetrySystemCallUi'] == true)) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
                      FilledButton.icon(
                        onPressed: opening.value ? null : openCurrentCallUi,
                        icon: const Icon(LucideIcons.phone),
                        label: Text(
                          opening.value
                              ? '正在打开…'
                              : data['canRetrySystemCallUi'] == true
                              ? '重试打开系统通话界面'
                              : calls.any((call) => call['state'] == 'ringing')
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
                onPressed: () =>
                    openRemoteRoute(context, deviceId: value(device, 'id')),
                icon: const Icon(LucideIcons.smartphone),
                label: const Text('打开手机屏幕'),
              ),
              TextButton(
                onPressed: () =>
                    AppsRoute(deviceId: value(device, 'id'))
                        .push<void>(context),
                child: const Text('从全部应用打开电话'),
              ),
              TextButton(
                onPressed: starting.value ? null : verify,
                child: Text(state == 'stopped' ? '启用通知与来电观察' : '重新核验通话'),
              ),
            ],
          );
        },
      ),
    );
  }
}
