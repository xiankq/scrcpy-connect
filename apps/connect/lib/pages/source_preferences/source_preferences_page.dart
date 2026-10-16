import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/audio_state.dart';
import 'package:scrcpy_connect/widgets/audio_source_card.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SourcePreferencesPage extends HookConsumerWidget {
  const SourcePreferencesPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDevices = ref.watch(
      appControllerProvider.select((state) => state.devices),
    );
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    final appAudioError = ref.watch(
      appControllerProvider.select((state) => state.audioError),
    );
    final revision = useState(0);
    final changing = useState(false);
    Future<bool> save(String key, dynamic next) async {
      try {
        await controller.updateSetting(key, next);
        return true;
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
        return false;
      }
    }

    return PageFrame(
      title: '设备音源',
      actions: [
        IconButton(
          tooltip: '刷新实际音源',
          onPressed: () => revision.value++,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: CommandView(
        controller: controller,
        command: 'audio.sources',
        refreshKey: '$appEventRevision:${revision.value}',
        emptyTitle: '暂时无法读取设备音源',
        builder: (context, data, refresh) {
          final sources = objects(data['sources']);
          Future<void> changeMode(String? mode) async {
            if (mode == null || changing.value) return;
            controller.cancelAudioFollow();
            final playing = sources.where(audioActive).toList();
            changing.value = true;
            try {
              if (mode != 'mix' && playing.length > 1) {
                final keep = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '选择保留的音源',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        for (final source in playing)
                          ListTile(
                            title: Text(sourceDeviceName(controller, source)),
                            subtitle: const Text('其他设备的声音将停止'),
                            onTap: () =>
                                Navigator.pop(context, audioId(source)),
                          ),
                      ],
                    ),
                  ),
                );
                if (keep == null || !context.mounted) return;
                for (final source in playing.where((s) => audioId(s) != keep)) {
                  await controller.request('audio.stop', {
                    'deviceId': source['deviceId'],
                    'sourceId': audioId(source),
                  });
                }
                final kept = playing.firstWhere((s) => audioId(s) == keep);
                if (!await save('audioDevices', [kept['deviceId']])) return;
              }
              await save('audioMode', mode);
              refresh();
            } catch (error) {
              if (context.mounted) feedback(context, '$error');
            } finally {
              if (context.mounted) {
                changing.value = false;
                refresh();
              }
            }
          }

          Future<void> toggle(Json device, Json? source) async {
            controller.cancelAudioFollow();
            final ids = List<Object?>.of(values(appSettings['audioDevices']));
            if (source != null && audioActive(source)) {
              await controller.request('audio.stop', {
                'deviceId': device['id'],
                'sourceId': audioId(source),
              });
              ids.remove(device['id']);
              // A user stop takes effect for follow behavior even when saving
              // the preference fails; a later focus must not restart it.
              controller.rememberAudioDevices(ids);
              await save('audioDevices', ids);
            } else {
              if (appSettings['audioMode'] != 'mix') {
                final others = sources
                    .where(
                      (s) => audioActive(s) && s['deviceId'] != device['id'],
                    )
                    .toList();
                for (final other in others) {
                  await controller.request('audio.stop', {
                    'deviceId': other['deviceId'],
                    'sourceId': audioId(other),
                  });
                }
                ids.clear();
              }
              final result = await controller.request('audio.start', {
                'deviceId': device['id'],
              });
              if (!context.mounted) return;
              if (result['status'] == 'playing') {
                if (!ids.contains(device['id'])) ids.add(device['id']);
                await save('audioDevices', ids);
              } else {
                feedback(
                  context,
                  value(result, 'reason', '尚未确认实际声音播放，请核验音源状态。'),
                );
              }
            }
            refresh();
          }

          final devices = [...appDevices];
          for (final source in sources) {
            if (!devices.any((d) => d['id'] == source['deviceId'])) {
              devices.add({
                'id': source['deviceId'],
                'name': value(source, 'deviceName', '未记录的设备'),
                'status': 'offline',
              });
            }
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const StateNote('同一手机的多个窗口共享一份设备声音。设备声音与通话双向语音是不同能力。'),
              for (final option in const [
                ('follow', '跟随当前操作设备'),
                ('fixed', '固定一台设备'),
                ('mix', '主动混音'),
              ])
                ChoiceRow<String>(
                  contentPadding: EdgeInsets.zero,
                  value: option.$1,
                  groupValue: value(appSettings, 'audioMode', 'follow'),
                  onChanged: changing.value ? null : changeMode,
                  title: Text(option.$2),
                ),
              if (appSettings['audioMode'] == 'mix')
                const StateNote('混音只播放你主动开启的音源；其他已连接设备不会自动加入。'),
              if (appAudioError != null)
                StateNote(appAudioError, icon: LucideIcons.circleAlert),
              const SectionTitle('实际音源'),
              if (devices.isEmpty) const StateNote('添加并连接设备后，即可检查该设备是否支持声音播放。'),
              for (final device in devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AudioSourceCard(
                    key: ValueKey(device['id']),
                    controller: controller,
                    device: device,
                    source: sources
                        .where((s) => s['deviceId'] == device['id'])
                        .firstOrNull,
                    onToggle: toggle,
                    onRefresh: refresh,
                  ),
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('后台声音'),
                subtitle: const Text('由你主动开启，在系统允许时继续播放'),
                value: appSettings['backgroundAudio'] == true,
                onChanged: (v) => save('backgroundAudio', v),
              ),
              const StateNote('通话保留自己的通信声音与麦克风路由。这里播放的设备声音不代表本机能够进行双向通话。'),
            ],
          );
        },
      ),
    );
  }
}
