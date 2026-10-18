import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AppearancePage extends HookConsumerWidget {
  const AppearancePage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    Future<void> save(String key, dynamic setting) async {
      try {
        await controller.updateSetting(key, setting);
      } catch (e) {
        if (context.mounted) feedback(context, '$e');
      }
    }

    return PageFrame(
      title: '外观与易用性',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          for (final option in const [
            ('light', '浅色', LucideIcons.sun),
            ('dark', '深色', LucideIcons.moon),
            ('system', '跟随系统', LucideIcons.monitor),
          ])
            ChoiceRow<String>(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(option.$3, size: 21),
                  const SizedBox(width: 14),
                  Text(option.$2),
                ],
              ),
              value: option.$1,
              groupValue: value(appSettings, 'appearance', 'light'),
              onChanged: (v) => save('appearance', v),
            ),
          const SectionTitle('易用性'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('降低透明度'),
            subtitle: const Text('以实色表面替代玻璃，保留明确边界'),
            value: appSettings['reduceTransparency'] == true,
            onChanged: (v) => save('reduceTransparency', v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('减少动态效果'),
            subtitle: const Text('减少空间位移，仍保留按下和状态反馈'),
            value: appSettings['reduceMotion'] == true,
            onChanged: (v) => save('reduceMotion', v),
          ),
          const StateNote(
            '文字大小跟随系统设置；页面允许换行与滚动，不通过缩小字号隐藏内容。系统增加对比时，控制层会保留更清晰的边界。',
          ),
        ],
      ),
    );
  }
}
