import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ClipboardPage extends HookConsumerWidget {
  const ClipboardPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDevices = ref.watch(
      appControllerProvider.select((state) => state.devices),
    );
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final appClipboardState = ref.watch(
      appControllerProvider.select((state) => state.clipboardState),
    );
    final appClipboardError = ref.watch(
      appControllerProvider.select((state) => state.clipboardError),
    );
    final knownIds = appDevices.map((d) => value(d, 'id')).toSet();
    final configuredDevice = value(appSettings, 'clipboardDevice');
    final selected = useState<String?>(
      knownIds.contains(configuredDevice) ? configuredDevice : null,
    );
    useEffect(() {
      final next = appSettings['clipboardMode'] == 'fixed'
          ? knownIds.contains(configuredDevice)
                ? configuredDevice
                : null
          : knownIds.contains(selected.value)
          ? selected.value
          : null;
      if (selected.value != next) selected.value = next;
      return null;
    }, [configuredDevice, appSettings['clipboardMode'], knownIds.join('|')]);
    Future<void> save(String key, dynamic next) async {
      try {
        await controller.updateSetting(key, next);
      } catch (e) {
        if (context.mounted) feedback(context, '$e');
      }
    }

    return PageFrame(
      title: '剪贴板同步',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动同步剪贴板'),
            subtitle: const Text('默认关闭，只在本应用前台与选定对象同步'),
            value: appSettings['clipboardSync'] == true,
            onChanged: (v) => save('clipboardSync', v),
          ),
          StateNote(switch (appClipboardState) {
            'watching' => '已开始核对并同步所选设备的新变化。',
            'checking' => '正在核对两端剪贴板与系统资格…',
            'waitingDevice' => '请选择已连接的固定对象，或打开要操作的设备工作台。',
            'waitingForeground' => '已暂停同步，回到本应用前台后重新核对。',
            'needsReview' => appClipboardError ?? '两端内容都已变化，请主动选择发送或获取。',
            'limited' => appClipboardError ?? '系统暂不允许自动同步，请主动核对。',
            _ => '自动同步尚未开启。主动发送与获取仍可单独使用。',
          }),
          const SectionTitle('同步对象'),
          for (final option in const [
            ('follow', '跟随当前操作设备'),
            ('fixed', '固定选择设备'),
          ])
            ChoiceRow<String>(
              contentPadding: EdgeInsets.zero,
              value: option.$1,
              groupValue: value(appSettings, 'clipboardMode', 'follow'),
              onChanged: (v) => save('clipboardMode', v),
              title: Text(option.$2),
            ),
          SectionTitle(
            appSettings['clipboardMode'] == 'fixed' ? '固定对象与主动操作' : '主动发送与获取',
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(selected.value),
            initialValue: selected.value,
            decoration: InputDecoration(
              labelText: appSettings['clipboardMode'] == 'fixed'
                  ? '固定同步对象'
                  : '主动操作设备',
            ),
            items: [
              for (final device in appDevices)
                DropdownMenuItem(
                  value: value(device, 'id'),
                  child: Text(
                    '${deviceName(device)} · ${statusText(value(device, 'status'))}',
                  ),
                ),
            ],
            onChanged: (v) async {
              selected.value = v;
              if (appSettings['clipboardMode'] == 'fixed') {
                await save('clipboardDevice', v);
              }
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: selected.value == null
                ? null
                : () async {
                    final clipboard = await Clipboard.getData(
                      Clipboard.kTextPlain,
                    );
                    if (!context.mounted) return;
                    if (clipboard?.text?.isNotEmpty != true) {
                      feedback(context, '本机剪贴板没有可发送的文字');
                      return;
                    }
                    final result = await perform(
                      context,
                      controller,
                      'clipboard.set',
                      {'deviceId': selected.value, 'text': clipboard!.text},
                    );
                    if (result != null && context.mounted) {
                      feedback(
                        context,
                        result['applied'] == true
                            ? value(result, 'message', '手机已确认剪贴板操作')
                            : value(
                                result,
                                'reason',
                                value(
                                  result,
                                  'message',
                                  '手机尚未确认写入，本机文字已保留。请在手机核对后再决定是否重新发送。',
                                ),
                              ),
                      );
                    }
                  },
            icon: const Icon(LucideIcons.send, size: 18),
            label: const Text('发送本机剪贴板'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: selected.value == null
                ? null
                : () async {
                    final result = await perform(
                      context,
                      controller,
                      'clipboard.get',
                      {'deviceId': selected.value},
                    );
                    if (result != null && result['text'] != null) {
                      await Clipboard.setData(
                        ClipboardData(text: value(result, 'text')),
                      );
                      if (context.mounted) feedback(context, '已复制到本机剪贴板');
                    }
                  },
            icon: const Icon(LucideIcons.clipboardCopy, size: 18),
            label: const Text('获取设备剪贴板'),
          ),
          const StateNote(
            '系统可能限制后台读取、敏感内容或过期内容。其他已连接设备不会因此自动覆盖本机剪贴板。本机始终不要求开启调试。',
          ),
          const StateNote(
            '开启或切换对象时先保留两端现有内容，之后同步新变化。离开前台暂停读取；返回后若两端都已变化，请主动选择发送或获取。',
          ),
        ],
      ),
    );
  }
}
