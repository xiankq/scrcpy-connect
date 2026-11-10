import 'dart:io';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/documents/document_export_form.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class ScreenshotPage extends HookWidget {
  const ScreenshotPage({
    super.key,
    required this.controller,
    required this.device,
    required this.capture,
  });

  final AppStore controller;
  final Json device, capture;

  @override
  Widget build(BuildContext context) {
    final path = value(capture, 'localPath');
    final saving = useState(false);
    final check = useMemoized(() async {
      if (capture['status'] != 'completed' ||
          capture['mime'] != 'image/png' ||
          !p.isAbsolute(path)) {
        return false;
      }
      return FileSystemEntity.type(
        path,
        followLinks: false,
      ).then((type) => type == FileSystemEntityType.file);
    }, [path]);
    final available = useFuture(check);
    final name = '截图-${p.basename(p.dirname(path))}.png';
    if (saving.value && available.data == true) {
      return PageFrame(
        title: '保存截图到系统位置',
        onBack: () => saving.value = false,
        child: DocumentExportForm(
          controller: controller,
          localPath: path,
          name: name,
          kind: 'file',
          sourceLabel: deviceName(device),
        ),
      );
    }
    return PageFrame(
      title: '截图',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          Text(
            '${deviceName(device)} · ${capture['paused'] == true ? '最后画面' : '当前视频帧'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          if (available.connectionState != ConnectionState.done)
            const Center(child: CircularProgressIndicator.adaptive())
          else if (available.data != true)
            const StateNote('截图暂存已不可用，请返回手机画面重新截图。')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
              child: Image.file(
                File(path),
                cacheWidth: 720,
                height: MediaQuery.sizeOf(context).height * .45,
                fit: BoxFit.contain,
                semanticLabel: capture['paused'] == true
                    ? '暂停前最后接收到的画面截图'
                    : '当前接收到的视频帧截图',
                errorBuilder: (_, _, _) =>
                    const StateNote('无法显示缩略图，仍可尝试保存原始截图。'),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            const Text('截图已取回本机暂存，尚未保存到系统位置。'),
            if (capture['width'] is num && capture['height'] is num)
              Text('${capture['width']} × ${capture['height']} 像素'),
            if (capture['paused'] == true)
              const StateNote('这是暂停前最后接收到的画面，并非手机当前实时画面。'),
            if (capture['scaled'] == true) const StateNote('受画面尺寸限制，截图已按比例缩小。'),
            const SizedBox(height: DesignTokens.spacingMd),
            if (supportsSystemDocumentSave) ...[
              FilledButton.icon(
                onPressed: () => saving.value = true,
                icon: const Icon(LucideIcons.download),
                label: const Text('保存到系统位置'),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
            ],
            if (supportsSystemFileShare)
              SystemFileShareForm(
                controller: controller,
                localPath: path,
                name: name,
                sourceLabel: deviceName(device),
              ),
          ],
        ],
      ),
    );
  }
}
