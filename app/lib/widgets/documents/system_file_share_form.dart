import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/documents/original_file_header.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:share_plus/share_plus.dart';

/// 选择过接收应用或交接待确认时，先核对再分享。
class SystemFileShareForm extends HookConsumerWidget {
  const SystemFileShareForm({
    super.key,
    required this.localPath,
    required this.name,
    this.kind = 'file',
    this.transferId,
    this.sourceLabel = '被控设备',
    this.role = AppButtonRole.primary,
  });
  final String localPath, name, kind, sourceLabel;
  final String? transferId;

  /// 分享按钮的角色。页面已有主动作（如「保存到系统位置」）时传次要角色，保持每屏一个主按钮。
  final AppButtonRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lease = useTransferCacheLease(ref, transferId);
    final busy = useState(false);
    final attempted = useState(false);
    final needsRecipientCheck = useState(false);
    final reviewed = useState(false);
    final outcome = useState<String?>(null);
    final ready = transferId == null || lease.hasData && !lease.hasError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OriginalFileHeader(name: name, kind: kind),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          '$sourceLabel → 本机暂存 → 接收应用',
          style: AppTypography.of(context).footnote
              .copyWith(color: AppColors.of(context).textSecondary),
        ),
        const StateNote('原文件尚未保存到系统位置。选择接收应用后，系统会交给它一份副本。'),
        if (defaultTargetPlatform == TargetPlatform.linux)
          const StateNote('此系统不支持文件分享面板，请使用保存到系统位置。')
        else if (kind == 'directory')
          const StateNote('当前系统分享不支持直接交付文件夹，请返回手机选择单个文件或使用已有传输方式。')
        else ...[
          if (lease.hasError)
            StateNote(
              failureMessage(lease.error, fallback: '临时文件已不可用。请从手机重新取回。'),
            ),
          if (!ready && !lease.hasError) const ContentLoadingIndicator(),
          if (outcome.value != null) StateNote(outcome.value!),
          if (needsRecipientCheck.value && !busy.value)
            CheckboxListTile(
              value: reviewed.value,
              onChanged: (value) => reviewed.value = value == true,
              title: const Text('我已在接收应用核对，仍需再次分享'),
            ),
          AppButton(
            role: role,
            expand: true,
            icon: AppIcons.share,
            onPressed:
                !ready ||
                    busy.value ||
                    needsRecipientCheck.value && !reviewed.value
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
                      if (context.mounted) {
                        outcome.value = result.message;
                        needsRecipientCheck.value = result.needsRecipientCheck;
                      }
                    } catch (error) {
                      if (context.mounted) {
                        needsRecipientCheck.value = true;
                        outcome.value = failureMessage(
                          error,
                          fallback: '暂时无法确认分享是否完成。请先查看接收文件的应用。',
                        );
                      }
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            label: busy.value
                ? '正在打开系统分享…'
                : attempted.value
                ? '再次系统分享'
                : '系统分享',
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

typedef PreparedFileShareReceipt = ({String message, bool needsRecipientCheck});

/// 完整原件在系统接收应用读取期间继续受到暂存保护。
Future<PreparedFileShareReceipt> sharePreparedFile(
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
    return (message: '原文件已保留，请返回传输详情继续分享。', needsRecipientCheck: false);
  }
  final render = context.findRenderObject();
  final origin = render is RenderBox && render.hasSize
      ? render.localToGlobal(Offset.zero) & render.size
      : null;
  final ShareResultStatus status;
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final receipt = await const PlatformChannels().request(
      'documents.shareFile',
      {
        'path': localPath,
        'viewId': View.of(context).viewId,
        if (origin != null) ...{
          'x': origin.left,
          'y': origin.top,
          'width': origin.width,
          'height': origin.height,
        },
      },
    );
    status = switch (receipt['selected']) {
      true => ShareResultStatus.success,
      false => ShareResultStatus.dismissed,
      _ => ShareResultStatus.unavailable,
    };
  } else {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(localPath)], sharePositionOrigin: origin),
    );
    status = result.status;
  }
  return switch (status) {
    ShareResultStatus.success => (
      message: '文件已交给所选应用。请打开该应用查看。',
      needsRecipientCheck: true,
    ),
    ShareResultStatus.dismissed => (
      message: '已关闭系统分享，原文件暂存仍保留。',
      needsRecipientCheck: false,
    ),
    ShareResultStatus.unavailable => (
      message: '暂时无法确认分享是否完成。请先打开接收文件的应用查看。',
      needsRecipientCheck: true,
    ),
  };
}
