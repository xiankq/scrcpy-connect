import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/core/media/audio_sources_notifier.dart';

/// 所有画面读取同一设备音源；静音只改变本机输出，不停止远端采集。
class RemoteAudioControl extends HookConsumerWidget {
  const RemoteAudioControl({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppNotifier controller;
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final device = state.devices
        .where((item) => item.id == deviceId)
        .firstOrNull;
    final online =
        device?.status == DeviceConnectionStatus.connected &&
        !state.reconciliationPending;
    final queryProvider = audioSourcesProvider(deviceId: deviceId);
    final query = ref.watch(queryProvider);
    final busy = useState(false);
    final failure = useState<String?>(null);
    final sources = query.sources ?? const <DeviceAudioSnapshot>[];
    final source = sources
        .where(
          (item) => <DeviceAudioStatus>[
            .starting,
            .playing,
            .paused,
          ].contains(item.status),
        )
        .firstOrNull;
    final cleanup = source == null
        ? sources.where((item) => item.cleanupError != null).firstOrNull
        : null;
    final target = source ?? cleanup;
    final sourceId = target?.sourceId ?? '';
    final muted = source?.muted == true;
    final paused =
        source?.status == DeviceAudioStatus.paused ||
        source?.requiresUserResume == true;
    final uncertain =
        failure.value != null ||
        target != null && sourceId.isEmpty ||
        query.error != null;
    final level = int.tryParse('${device?.apiLevel}');
    final unsupported = level != null && level < 30;
    final label = uncertain
        ? '重新核对设备声音'
        : cleanup != null
        ? '重试声音清理'
        : paused
        ? '恢复设备声音'
        : muted || source == null
        ? '播放设备声音'
        : '静音设备声音';
    final status = !online
        ? '连接未确认，声音状态待核对'
        : unsupported
        ? '设备声音需要 Android 11 或更新版本'
        : uncertain
        ? failure.value ?? (query.error?.toString() ?? '声音快照未能核验')
        : cleanup != null
        ? '旧音源尚未确认释放，清理完成后可重新播放。'
        : query.loading || source?.status == DeviceAudioStatus.starting
        ? '正在核对声音状态'
        : muted
        ? '本机已静音，手机采集状态不受影响'
        : paused
        ? '设备声音待恢复'
        : source?.status == DeviceAudioStatus.playing
        ? '正在播放设备声音'
        : source?.reason ?? '设备声音尚未播放';
    return ListTile(
      leading: Icon(muted ? LucideIcons.volumeX : LucideIcons.volume2),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: Text(status),
      enabled: online && !unsupported && !busy.value && !query.loading,
      onTap: !online || unsupported || busy.value || query.loading
          ? null
          : () async {
              busy.value = true;
              try {
                if (!uncertain) {
                  final views = RemoteViewsScope.of(context);
                  final audioTarget = DeviceAudioTarget(
                    deviceId: deviceId,
                    sourceId: target?.sourceId,
                  );
                  if (cleanup != null) {
                    await controller.remoteAudio.stopAudio(audioTarget);
                  } else if (source == null) {
                    await views.startAudio(deviceId);
                  } else if (paused) {
                    await views.resumeAudio(audioTarget);
                  } else {
                    await controller.remoteAudio.changeAudioVolume(
                      audioTarget,
                      muted: !muted,
                    );
                  }
                }
                await ref.read(queryProvider.notifier).refresh();
                if (context.mounted) failure.value = null;
              } catch (error) {
                if (context.mounted) failure.value = '$error';
              } finally {
                if (context.mounted) busy.value = false;
              }
            },
    );
  }
}
