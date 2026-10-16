import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/audio_state.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AudioSourceCard extends HookWidget {
  const AudioSourceCard({
    super.key,
    required this.controller,
    required this.device,
    required this.source,
    required this.onToggle,
    required this.onRefresh,
  });
  final AppController controller;
  final Json device;
  final Json? source;
  final Future<void> Function(Json, Json?) onToggle;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    final volume = useState<double?>(null);
    final actualVolume = (num.tryParse('${source?['volume']}') ?? 1)
        .toDouble()
        .clamp(0.0, 1.0);
    final active = source != null && audioActive(source!);
    Future<void> adjust(double next, bool muted) async {
      if (source == null) return;
      busy.value = true;
      await perform(context, controller, 'audio.volume', {
        'deviceId': device['id'],
        'sourceId': audioId(source!),
        'volume': next,
        'muted': muted,
      });
      if (!context.mounted) return;
      volume.value = null;
      busy.value = false;
      onRefresh();
    }

    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FeatureIcon(
                active ? LucideIcons.volume2 : LucideIcons.volumeX,
                color: ConnectTokens.mint,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(device),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      audioStatus(source),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: active ? '停止此设备声音' : '播放此设备声音',
                onPressed:
                    busy.value || (!active && device['status'] != 'connected')
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          await onToggle(device, source);
                        } catch (error) {
                          if (context.mounted) feedback(context, '$error');
                        } finally {
                          if (context.mounted) {
                            busy.value = false;
                            onRefresh();
                          }
                        }
                      },
                icon: busy.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        active ? LucideIcons.square : LucideIcons.play,
                        size: 20,
                      ),
              ),
            ],
          ),
          if (value(source ?? {}, 'reason').isNotEmpty)
            StateNote(value(source!, 'reason'), icon: LucideIcons.info),
          if (!active && device['status'] != 'connected')
            const StateNote('设备当前离线，恢复连接后才可播放声音。'),
          if (active) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  tooltip: source!['muted'] == true ? '取消静音' : '静音',
                  onPressed: busy.value
                      ? null
                      : () => adjust(actualVolume, source!['muted'] != true),
                  icon: Icon(
                    source!['muted'] == true
                        ? LucideIcons.volumeX
                        : LucideIcons.volume2,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: volume.value ?? actualVolume,
                    onChanged: busy.value ? null : (v) => volume.value = v,
                    onChangeEnd: (v) => adjust(v, source!['muted'] == true),
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  ),
                ),
                Text(
                  '${((volume.value ?? actualVolume) * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
