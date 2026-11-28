import 'dart:async';
import 'dart:io';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/app_release.dart';
import 'package:scrcpy_connect/core/platform/app_update_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/status_tag.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdatesPage extends HookConsumerWidget {
  const AppUpdatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(appInfoReaderProvider);
    final channel = ref.watch(appUpdateReaderProvider);
    final info = useFuture(useMemoized(read, [read]));
    final releases = useState<List<AppRelease>>([]);
    final checking = useState(false);
    final status = useState<String?>(null);
    final installed = info.data;
    final newer = installed == null
        ? null
        : releases.value
              .where((release) => release.isNewerThan(installed))
              .fold<AppRelease?>(
                null,
                (latest, release) =>
                    latest == null || release.compareTo(latest) > 0
                    ? release
                    : latest,
              );

    void showHistory() {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => PageFrame(
            title: '更新记录',
            onBack: () => Navigator.pop(context),
            child: GroupedListView(
              padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
              children: [
                if (releases.value.isEmpty)
                  SettingsGroup(
                    children: [
                      AppListRow(
                        title: Text(
                          installed == null
                              ? '暂无可用的版本记录'
                              : '已安装 ${installed.version}',
                        ),
                        subtitle: Text(
                          channel == null
                              ? '这个版本暂时无法在应用内检查更新。'
                              : '检查更新后可查看发布说明。',
                        ),
                      ),
                    ],
                  ),
                for (final release in releases.value)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacingLg,
                    ),
                    child: _ReleaseCard(
                      release: release,
                      installed:
                          installed != null && release.matches(installed),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Future<void> present(AppRelease latest, AppInfo current) async {
      final result = await showAppDialog<String>(
        context: context,
        builder: (context) => _UpdatePrompt(latest: latest, current: current),
      );
      if (!context.mounted) return;
      if (result == 'history') showHistory();
      if (result == 'open') {
        await performAction(context, () async {
          if (!await launchUrl(
            latest.url,
            mode: LaunchMode.externalApplication,
          )) {
            throw StateError('无法打开更新页面。');
          }
        }, failure: '无法打开更新页面。请检查网络后重试。');
      }
    }

    Future<void> check() async {
      if (checking.value) return;
      if (channel == null) {
        status.value = '这个版本暂时无法在应用内检查更新。';
        return;
      }
      if (installed == null) return;
      checking.value = true;
      status.value = '正在检查…';
      final List<AppRelease> accepted;
      try {
        accepted = await channel();
      } on Exception catch (error) {
        final reason = switch (error) {
          FormatException() => '无法读取更新记录',
          SocketException() || TimeoutException() => '连接更新服务超时或中断。请稍后重试。',
          HttpException() => '更新服务暂时不可用。请稍后重试。',
          TlsException() => '无法验证更新服务。请稍后重试。',
          _ => null,
        };
        if (reason == null) rethrow;
        if (context.mounted) status.value = reason;
        return;
      } finally {
        if (context.mounted) checking.value = false;
      }
      if (!context.mounted) return;
      AppRelease? latest;
      for (final release in accepted) {
        if (release.isNewerThan(installed) &&
            (latest == null || release.compareTo(latest) > 0)) {
          latest = release;
        }
      }
      releases.value = accepted;
      status.value = latest == null ? '已是最新版本' : '发现 ${latest.version}';
      if (latest != null) await present(latest, installed);
    }

    return PageFrame(
      title: '关于与更新',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          SettingsGroup(
            children: [
              AppListRow(
                leading: const ListIconBadge(
                  icon: LucideIcons.info,
                  backgroundColor: FunctionTone.utility,
                ),
                title: const Text('当前版本'),
                value: installed == null
                    ? (info.hasError ? '读取失败' : '读取中…')
                    : '${installed.version}（构建 ${installed.buildNumber}）',
              ),
              AppListRow(
                leading: const ListIconBadge(
                  icon: AppIcons.refresh,
                  backgroundColor: FunctionTone.utility,
                ),
                title: const Text('检查更新'),
                subtitle: status.value == null ? null : Text(status.value!),
                trailing: checking.value
                    ? null
                    : AppButton(
                        size: AppButtonSize.section,
                        onPressed: check,
                        label: '检查',
                      ),
                onTap: checking.value ? null : check,
              ),
              if (newer != null && installed != null)
                ActionRow(
                  icon: AppIcons.download,
                  color: FunctionTone.transfer,
                  title: '发现新版本 ${newer.version}',
                  onTap: () => present(newer, installed),
                ),
              AppListRow(
                leading: const ListIconBadge(
                  icon: LucideIcons.history,
                  backgroundColor: FunctionTone.archive,
                ),
                title: const Text('更新记录'),
                chevron: true,
                onTap: showHistory,
              ),
            ],
          ),
          const SectionTitle('关于'),
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.fileText,
                title: '开源许可',
                value: 'Lucide、FFmpeg 等',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '邻接 Interconnect',
                  applicationVersion: installed?.version,
                  applicationLegalese: '媒体解码使用 LGPL 2.1 或更高版本许可的 FFmpeg。',
                ),
              ),
              const ActionRow(
                icon: LucideIcons.monitorSmartphone,
                title: '跨设备互联',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 版本说明卡（Ardot 41:565）：版本号 `headline` + 状态标签，日期在右上，下方逐条说明。
class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.installed});
  final AppRelease release;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: DesignTokens.spacingSm,
            children: [
              Flexible(child: Text(release.version, style: type.title3)),
              if (installed)
                const StatusTag('已安装', tone: StatusTagTone.success),
              const Spacer(),
              Text(
                MaterialLocalizations.of(context)
                    .formatMediumDate(release.publishedAt.toLocal()),
                style: type.footnote.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          if (release.notes.isNotEmpty)
            const SizedBox(height: DesignTokens.spacingSm),
          _ReleaseNotes(release.notes),
        ],
      ),
    );
  }
}

/// 逐条更新说明：`subheadline` + `text-secondary`，每条前加间隔点。
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes(this.notes);
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.of(context).subheadline
        .copyWith(color: AppColors.of(context).textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in notes)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text('· ', style: style)),
              Expanded(child: Text(note, style: style)),
            ],
          ),
      ],
    );
  }
}

/// 更新弹窗中宽版的宽度与左栏宽（Ardot W11 9:1785：弹窗 640、左栏 220）。
const _wideDialogWidth = 640.0;
const _wideSummaryWidth = 220.0;

/// 宽版弹窗只在矮于 480 的窗口里使用，纵排放不下时才改横排（Ardot W11 9:1785 为 430 高）。
const _wideDialogMaxHeight = 480.0;

/// 宽版左栏的下载图形块（Ardot W11 9:1785）：56 方块、图形 28。
const _wideIconSize = 56.0;
const _wideGlyphSize = 28.0;

class _UpdatePrompt extends StatelessWidget {
  const _UpdatePrompt({required this.latest, required this.current});
  final AppRelease latest;
  final AppInfo current;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final title = Text('发现新版本 ${latest.version}', style: type.headline);
    final detail = Text(
      [
        '当前 ${current.version}',
        if (latest.bytes case final bytes?)
          '安装包 ${(bytes / 1048576).toStringAsFixed(1)} MB',
      ].join(' · '),
      style: type.subheadline.copyWith(color: colors.textSecondary),
    );
    // 本次更新：确认框内的内嵌块，玻璃上用 glass-fill，实体面上用 block（Ardot 41:520）。
    final notes = DecoratedBox(
      decoration: ShapeDecoration(
        color: opaqueGlass(context) ? colors.block : colors.glassFill,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.roundedLg),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingLg,
          DesignTokens.spacingSm,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '本次更新',
                    style: type.captionEmphasis.copyWith(color: colors.text),
                  ),
                ),
                AppButton(
                  role: AppButtonRole.text,
                  size: AppButtonSize.section,
                  onPressed: () => Navigator.pop(context, 'history'),
                  label: '查看更新记录',
                ),
              ],
            ),
            _ReleaseNotes(latest.notes),
          ],
        ),
      ),
    );
    void later() => Navigator.pop(context);
    void open() => Navigator.pop(context, 'open');
    final media = MediaQuery.of(context);
    final wide =
        media.size.height - media.viewInsets.vertical < _wideDialogMaxHeight &&
        media.size.width - media.padding.horizontal >=
            _wideDialogWidth + 2 * DesignTokens.spacingLg;
    if (!wide) {
      return AppAlertDialog(
        glass: true,
        title: Text('发现新版本 ${latest.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignTokens.spacingLg,
          children: [detail, notes],
        ),
        actions: [
          TextButton(onPressed: later, child: const Text('稍后')),
          FilledButton(onPressed: open, child: const Text('前往发布渠道')),
        ],
      );
    }
    // 宽版（Ardot W11 9:1785）：左栏图形与版本，右栏更新说明与动作，材质同确认框。
    return Dialog(
      backgroundColor: colors.card.withAlpha(0),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingLg,
        vertical: DesignTokens.spacingSm,
      ),
      constraints: const BoxConstraints.tightFor(width: _wideDialogWidth),
      clipBehavior: Clip.none,
      child: Glass(
        variant: GlassVariant.alert,
        radius: DesignTokens.componentAlertRounded,
        padding: const EdgeInsets.all(DesignTokens.spacingXxl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignTokens.spacingXxl,
          children: [
            SizedBox(
              width: _wideSummaryWidth,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: _wideIconSize,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: colors.primaryContainer,
                            shape: const RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(DesignTokens.roundedMd),
                              ),
                            ),
                          ),
                          child: Icon(
                            AppIcons.download,
                            size: _wideGlyphSize,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingLg),
                    title,
                    const SizedBox(height: DesignTokens.spacingXs),
                    detail,
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: SingleChildScrollView(child: notes)),
                  const SizedBox(height: DesignTokens.spacingMd),
                  Row(
                    spacing: DesignTokens.componentAlertActionsGap,
                    children: [
                      Expanded(
                        child: AppButton(
                          role: AppButtonRole.secondaryOnGlass,
                          expand: true,
                          onPressed: later,
                          label: '稍后',
                        ),
                      ),
                      Expanded(
                        child: AppButton(
                          role: AppButtonRole.primary,
                          expand: true,
                          onPressed: open,
                          label: '前往发布渠道',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
