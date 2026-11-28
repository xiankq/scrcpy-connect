import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class GalleryScopeSheet extends StatelessWidget {
  const GalleryScopeSheet({
    super.key,
    required this.device,
    required this.snapshot,
  });
  final DeviceSnapshot device;
  final GalleryScanSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final issues = snapshot.issues;
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Padding(
          padding: const EdgeInsets.only(bottom: DesignTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: '本次检查范围'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentSheetPadding,
                ),
                child: Text(
                  '${deviceName(device)} · ${snapshot.total} 项结果',
                  style: type.subheadline.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Expanded(
                child: CustomScrollView(
                  primary: false,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.componentSheetPadding,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const StateNote(
                              '检查当前手机共享存储中的照片与视频，包含下载和自定义文件夹；按文件扩展名识别，文件修改时间不等于拍摄时间。',
                            ),
                            StateNote(
                              '范围：${snapshot.scope.roots.join('、')}\n不包含：${snapshot.scope.excluded.join('、')}',
                            ),
                            const StateNote(
                              '这里显示上次读取的照片和视频。想查看手机上的最新内容，可以下拉刷新。',
                            ),
                            if (issues.isNotEmpty)
                              Text(
                                '未完整检查 · ${issues.length} 处',
                                style: type.headline,
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.componentSheetPadding,
                      ),
                      sliver: SliverList.builder(
                        itemCount: issues.length,
                        itemBuilder: (context, index) {
                          final issue = issues[index];
                          final code = issue.code;
                          final reason = code.endsWith('_limit')
                              ? '本次检查达到可处理范围，部分内容尚未列出；可在手机原应用继续查看。'
                              : failureCodeMessage(
                                  issue.code,
                                  fallback: '无法读取这个位置。请检查手机上的文件访问权限。',
                                );
                          return StateNote(
                            '${issue.path}\n$reason',
                            icon: LucideIcons.folderLock,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentSheetPadding,
                ),
                child: AppButton(
                  label: '关闭范围',
                  expand: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
