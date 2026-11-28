import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';

import 'share_submission_notifier.dart';

import 'package:scrcpy_connect/pages/incoming_share/widgets/share_device_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/grouped_list_segment.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/input_field.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class IncomingSharePage extends HookConsumerWidget {
  const IncomingSharePage({super.key, required this.share});
  final IncomingShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(
      shareInboxProvider.select(
        (state) => state.shares
            .where((item) => item.shareId == this.share.shareId)
            .firstOrNull,
      ),
    );
    final share = latest ?? this.share;
    final directorySource = ref.watch(fileDirectoriesProvider);
    final scope = useMemoized(Object.new, [share.shareId]);
    final provider = shareSubmissionProvider(share.shareId, scope: scope);
    final submission = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    useEffect(() {
      if (!submission.completed) return null;
      var cancelled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (cancelled || !context.mounted || !ref.read(provider).completed) {
          return;
        }
        closePage<void>(context);
        if (submission.showTransfers && context.mounted) {
          const TransferCenterRoute().push<void>(context);
        }
      });
      return () => cancelled = true;
    }, [provider, submission]);
    final appDevices = ref.watch(
      deviceListProvider.select((state) => state.devices),
    );
    final files = share.files;
    final text = share.text;
    final importing = [
      IncomingShareStatus.starting,
      IncomingShareStatus.importing,
    ].contains(share.status);
    final deviceId = useState<String?>(null);
    final path = useTextEditingController(text: '/sdcard/Download');
    useListenable(path);
    final includeFiles = useState(true);
    final includeText = useState(text.isNotEmpty);
    final locked = submission.pushed || submission.copied;
    final devices = appDevices
        .where((d) => d.status == DeviceConnectionStatus.connected)
        .toList();
    final selected = devices.where((d) => d.id == deviceId.value).firstOrNull;
    final needsPush =
        includeFiles.value && files.isNotEmpty && !submission.pushed;
    final needsCopy = includeText.value && !submission.copied;
    final canSubmit =
        latest != null &&
        !submission.busy &&
        !importing &&
        (selected != null || (!needsPush && !needsCopy)) &&
        ((includeFiles.value && files.isNotEmpty) || includeText.value) &&
        (!needsPush ||
            (path.text.startsWith('/') && !path.text.contains('\u0000')));

    Future<void> submit() => actions.submit(
      deviceId: deviceId.value,
      directory: path.text,
      includeFiles: includeFiles.value,
      includeText: includeText.value,
    );

    final hasReadError = share.errors.isNotEmpty;
    final leading = <Widget>[
      if (latest == null && !submission.busy && !submission.completed)
        const StateNote('这次分享已处理或来源已变化，请重新从系统分享。'),
      if (importing) ...[
        const ContentLoadingIndicator(),
        const StateNote('正在读取分享内容，完成后即可发送。你也可以取消本次分享。'),
      ],
    ];
    final fileHeader = <Widget>[
      if (files.isNotEmpty)
        GroupedListSegment(
          first: true,
          last: false,
          child: ConnectSwitchRow(
            title: Text('传入 ${files.length} 个文件'),
            value: includeFiles.value,
            onChanged: submission.busy || locked
                ? null
                : (v) => includeFiles.value = v,
          ),
        ),
    ];
    final middle = <Widget>[
      if (text.isNotEmpty) ...[
        if (files.isNotEmpty) const SizedBox(height: DesignTokens.spacingXxl),
        SettingsGroup(
          children: [
            ConnectSwitchRow(
              title: const Text('写入设备剪贴板'),
              value: includeText.value,
              onChanged: submission.busy || locked
                  ? null
                  : (v) => includeText.value = v,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.componentListRowPadding,
                DesignTokens.spacingMd,
                DesignTokens.componentListRowPadding,
                DesignTokens.componentListRowPadding,
              ),
              child: SelectableText(text),
            ),
          ],
        ),
      ],
      const SectionTitle('接收设备'),
      if (devices.isEmpty)
        const StateNote('当前没有已连接设备。先恢复设备连接，再返回这里选择；也可以取消本次分享。'),
    ];
    final trailing = <Widget>[
      if (includeFiles.value && files.isNotEmpty) ...[
        const SectionTitle('目标目录'),
        AppTextField(
          controller: path,
          enabled: !submission.busy && !locked,
          label: '设备上的完整目录',
          helperText: '同名文件会在传输中心等待你确认',
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        AppButton(
          role: AppButtonRole.secondaryOnPage,
          expand: true,
          onPressed: selected == null || submission.busy || locked
              ? null
              : () async {
                  final directory = await ShareDirectoryRoute(
                    deviceId: selected.id,
                    path: path.text,
                  ).push<String>(context);
                  if (directory != null &&
                      context.mounted &&
                      identical(
                        ref.read(fileDirectoriesProvider),
                        directorySource,
                      ) &&
                      deviceId.value == selected.id &&
                      !ref.read(provider).busy) {
                    path.text = directory;
                  }
                },
          icon: LucideIcons.folderOpen,
          label: '浏览设备目录',
        ),
      ],
      if (selected != null)
        StateNote(
          '本次目标：${deviceName(selected)}${includeFiles.value ? ' · ${path.text}' : ' · 剪贴板'}',
        ),
      if (submission.pushed) const StateNote('文件任务已提交；再次确认不会重复提交这批文件。'),
      if (submission.copied) const StateNote('文字已写入指定设备剪贴板。'),
      if (submission.error != null)
        StateNote(submission.error!, icon: LucideIcons.circleAlert),
      const SizedBox(height: DesignTokens.spacingMd),
      if (submission.busy)
        const Padding(
          padding: EdgeInsets.all(DesignTokens.spacingMd),
          child: ContentLoadingIndicator(),
        ),
    ];
    final errorsStart = leading.length;
    final fileHeaderStart = errorsStart + (hasReadError ? 1 : 0);
    final filesStart = fileHeaderStart + fileHeader.length;
    final middleStart = filesStart + files.length;
    final devicesStart = middleStart + middle.length;
    final trailingStart = devicesStart + devices.length;
    final indices = <Key, int>{
      if (hasReadError) const ValueKey('incoming-error'): errorsStart,
      for (var index = 0; index < files.length; index++)
        ValueKey(('incoming-file', share.shareId, index)): filesStart + index,
      for (var index = 0; index < devices.length; index++)
        ValueKey(('incoming-device', devices[index].id)): devicesStart + index,
    };

    return PopScope(
      canPop: submission.completed,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) actions.cancel();
      },
      child: PageFrame(
        title: files.isEmpty && text.isNotEmpty
            ? '发送文字'
            : files.isNotEmpty && text.isEmpty
            ? '发送文件'
            : '发送到设备',
        bottom: AppButton(
          role: AppButtonRole.primary,
          expand: true,
          onPressed: canSubmit ? submit : null,
          label: submission.busy
              ? '正在提交…'
              : locked
              ? '继续完成'
              : includeFiles.value && files.isNotEmpty
              ? '确认发送'
              : '写入设备剪贴板',
        ),
        trailingAction: AppButton(
          role: AppButtonRole.text,
          size: AppButtonSize.section,
          onPressed: submission.busy ? null : actions.cancel,
          label: locked ? '关闭' : '取消',
        ),
        child: GroupedListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
          ),
          itemCount: trailingStart + trailing.length,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) {
            if (index < errorsStart) return leading[index];
            if (index < fileHeaderStart) {
              return StateNote(
                '有些分享内容无法读取。请回原应用重新分享这些内容。',
                key: const ValueKey('incoming-error'),
                icon: LucideIcons.circleAlert,
              );
            }
            if (index < filesStart) return fileHeader[index - fileHeaderStart];
            if (index < middleStart) {
              final row = index - filesStart;
              return GroupedListSegment(
                key: ValueKey(('incoming-file', share.shareId, row)),
                first: false,
                last: row == files.length - 1,
                child: ActionRow(
                  icon: LucideIcons.file,
                  color: FunctionTone.file,
                  title: files[row].name,
                  value: fileSizeLabel(files[row].size),
                ),
              );
            }
            if (index < devicesStart) return middle[index - middleStart];
            if (index >= trailingStart) return trailing[index - trailingStart];
            final device = devices[index - devicesStart];
            return Padding(
              key: ValueKey(('incoming-device', device.id)),
              padding: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
              child: ShareDeviceCard(
                device: device,
                selected: deviceId.value == device.id,
                onTap: submission.busy || locked
                    ? null
                    : () => deviceId.value = device.id,
              ),
            );
          },
        ),
      ),
    );
  }
}
