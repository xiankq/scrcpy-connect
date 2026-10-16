import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BackgroundPage extends HookConsumerWidget {
  const BackgroundPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final changing = useState(false);
    final revision = useState(0);
    return PageFrame(
      title: '后台与连接',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许后台保持'),
            subtitle: const Text('在系统允许时，维持已经开启的连接与活动'),
            value: appSettings['backgroundKeepAlive'] == true,
            onChanged: changing.value
                ? null
                : (v) async {
                    changing.value = true;
                    try {
                      await controller.updateSetting('backgroundKeepAlive', v);
                      await controller.request('background.request', {
                        'enabled': v,
                        'askNotificationPermission': v,
                      });
                    } catch (e) {
                      if (context.mounted) feedback(context, '$e');
                    } finally {
                      if (context.mounted) {
                        changing.value = false;
                        revision.value++;
                      }
                    }
                  },
          ),
          CommandView(
            controller: controller,
            command: 'background.status',
            refreshKey: revision.value,
            emptyTitle: '尚未获得后台运行资格',
            builder: (context, data, refresh) => ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value(data, 'title', '系统后台条件'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(value(data, 'reason', '后台运行取决于系统授权、电量策略与活动类型。')),
                  if (data['canRequest'] == true)
                    TextButton(
                      onPressed: () async {
                        await perform(
                          context,
                          controller,
                          'background.request',
                          {'enabled': true, 'askNotificationPermission': true},
                        );
                        refresh();
                      },
                      child: const Text('检查系统设置'),
                    ),
                ],
              ),
            ),
          ),
          const SectionTitle('离开前台后'),
          const ActionRow(
            icon: LucideIcons.link,
            title: '连接与通知',
            subtitle: '仅按已启用的活动和实际系统资格保持',
          ),
          const ActionRow(
            icon: LucideIcons.arrowUpDown,
            title: '文件传输',
            subtitle: '显示实际进度；中断后检查内容和恢复资格',
            color: ConnectTokens.amber,
          ),
          const ActionRow(
            icon: LucideIcons.pause,
            title: '不可见画面',
            subtitle: '暂停视频，回到前台后等待新画面',
          ),
          const ActionRow(
            icon: LucideIcons.audioLines,
            title: '声音与通话',
            subtitle: '后台声音需主动开启；通话按实际链路保持',
            color: ConnectTokens.mint,
          ),
          const StateNote(
            '系统停止、强行结束或回收应用后，不保证活动仍在进行。再次打开会核验状态；用户主动停止的活动保持停止，未知结果的回复、删除和拨号不会自动重复。',
          ),
          OutlinedButton(
            onPressed: () => ActivitiesRoute().push<void>(context),
            child: const Text('查看并停止当前活动'),
          ),
        ],
      ),
    );
  }
}
