import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/documents/original_file_header.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:share_plus/share_plus.dart';

/// 系统分享只有交接回执；再次提交必须先核对接收应用，不能当作保存完成。
class SystemFileShareForm extends HookConsumerWidget {
  const SystemFileShareForm({
    super.key,
    required this.localPath,
    required this.name,
    this.kind = 'file',
    this.transferId,
    this.sourceLabel = '被控设备',
  });
  final String localPath, name, kind, sourceLabel;
  final String? transferId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lease = useTransferCacheLease(ref, transferId);
    final busy = useState(false);
    final attempted = useState(false);
    final reviewed = useState(false);
    final outcome = useState<String?>(null);
    final ready = transferId == null || lease.hasData && !lease.hasError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OriginalFileHeader(name: name, kind: kind),
        const SizedBox(height: DesignTokens.spacingMd),
        Text('$sourceLabel → 本机暂存 → 接收应用'),
        const StateNote(
          '原文件尚未保存到系统位置。系统分享将副本交给选择的应用；请在接收应用核对实际读取、保存或发送结果。本机原件继续保留。',
        ),
        if (defaultTargetPlatform == TargetPlatform.linux)
          const StateNote('此系统不支持文件分享面板，请使用保存到系统位置。')
        else if (kind == 'directory')
          const StateNote('当前系统分享不支持直接交付文件夹，请返回手机选择单个文件或使用已有传输方式。')
        else ...[
          if (lease.hasError) StateNote('无法保留这份暂存：${lease.error}'),
          if (!ready && !lease.hasError) const ContentLoadingIndicator(),
          if (outcome.value != null) StateNote(outcome.value!),
          if (attempted.value && !busy.value)
            CheckboxListTile(
              value: reviewed.value,
              onChanged: (value) => reviewed.value = value == true,
              title: const Text('我已在接收应用核对，仍需再次分享'),
            ),
          FilledButton.icon(
            onPressed:
                !ready || busy.value || attempted.value && !reviewed.value
                ? null
                : () async {
                    busy.value = true;
                    attempted.value = true;
                    reviewed.value = false;
                    try {
                      final result = await sharePreparedFile(
                        context,
                        ref,
                        localPath,
                      );
                      if (context.mounted) outcome.value = result;
                    } catch (error) {
                      if (context.mounted) {
                        outcome.value = '系统分享结果未确认：$error。请先在接收应用核对。';
                      }
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            icon: const Icon(Icons.share_outlined),
            label: Text(
              busy.value
                  ? '正在打开系统分享…'
                  : attempted.value
                  ? '再次系统分享'
                  : '系统分享',
            ),
          ),
        ],
      ],
    );
  }
}

bool get supportsSystemFileShare =>
    defaultTargetPlatform != TargetPlatform.linux;
bool get supportsSystemDocumentSave => const {
  TargetPlatform.android,
  TargetPlatform.linux,
}.contains(defaultTargetPlatform);

/// 完整原件在系统接收应用读取期间继续受到暂存保护。
Future<String> sharePreparedFile(
  BuildContext context,
  WidgetRef ref,
  String localPath,
) async {
  if (!supportsSystemFileShare) {
    throw const RequestFailure(
      'platform_unavailable',
      '此系统不支持文件分享，请选择保存到系统位置。',
    );
  }
  final cache = ref.read(contentCacheControlProvider);
  await cache.retain(localPath, ifManaged: true);
  if (!context.mounted ||
      !identical(ref.read(contentCacheControlProvider), cache)) {
    return '原文件已保留，请返回传输详情继续分享。';
  }
  final render = context.findRenderObject();
  final origin = render is RenderBox && render.hasSize
      ? render.localToGlobal(Offset.zero) & render.size
      : null;
  final result = await SharePlus.instance.share(
    ShareParams(files: [XFile(localPath)], sharePositionOrigin: origin),
  );
  return switch (result.status) {
    ShareResultStatus.success => '已交给系统选择的应用，请在接收应用核对。',
    ShareResultStatus.dismissed => '已关闭系统分享，原文件暂存仍保留。',
    ShareResultStatus.unavailable => '系统没有提供分享结果，请在接收应用核对；不会自动重复分享。',
  };
}
