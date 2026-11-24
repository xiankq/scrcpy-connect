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
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
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
    final theme = Theme.of(context);
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
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              children: [
                if (releases.value.isEmpty)
                  ListTile(
                    title: Text(
                      installed == null
                          ? '暂无可用的版本记录'
                          : '已安装 ${installed.version}',
                    ),
                    subtitle: Text(
                      channel == null ? '这个版本暂时无法在应用内检查更新。' : '检查更新后可查看发布说明。',
                    ),
                  ),
                for (final release in releases.value)
                  SettingsGroup(
                    children: [
                      ListTile(
                        title: Text(release.version),
                        subtitle: Text(
                          MaterialLocalizations.of(context)
                              .formatMediumDate(release.publishedAt.toLocal()),
                        ),
                        trailing:
                            installed != null && release.matches(installed)
                            ? const Text('已安装')
                            : null,
                      ),
                      for (final note in release.notes)
                        ListTile(
                          leading: const Icon(LucideIcons.dot),
                          title: Text(note),
                        ),
                    ],
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
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          SettingsGroup(
            children: [
              ListTile(
                leading: const FeatureIcon(
                  LucideIcons.circleHelp,
                  size: DesignTokens.componentListIconSize,
                ),
                title: Row(
                  children: [
                    const Expanded(child: Text('当前版本')),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(
                      child: installed == null
                          ? _UpdateStatus(text: info.hasError ? '读取失败' : '读取中…')
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  installed.version,
                                  style: theme.textTheme.titleMedium,
                                  textAlign: TextAlign.end,
                                ),
                                Text(
                                  '构建 ${installed.buildNumber}',
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.end,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const FeatureIcon(
                  AppIcons.refresh,
                  size: DesignTokens.componentListIconSize,
                ),
                title: const Text('检查更新'),
                trailing: status.value == null
                    ? const Icon(
                        AppIcons.forward,
                        size: DesignTokens.componentIconSmallSize,
                      )
                    : _UpdateStatus(text: status.value!),
                onTap: checking.value ? null : check,
              ),
              if (newer != null && installed != null)
                ActionRow(
                  icon: LucideIcons.arrowUpCircle,
                  title: '发现新版本 ${newer.version}',
                  onTap: () => present(newer, installed),
                ),
              ListTile(
                leading: const FeatureIcon(
                  LucideIcons.layers3,
                  size: DesignTokens.componentListIconSize,
                ),
                title: const Text('更新记录'),
                trailing: const Icon(
                  AppIcons.forward,
                  size: DesignTokens.componentIconSmallSize,
                ),
                onTap: showHistory,
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          SettingsGroup(
            children: [
              const ActionRow(
                icon: LucideIcons.monitorSmartphone,
                title: '跨设备互联',
                color: DesignTokens.colorListIconMint,
              ),
              ActionRow(
                icon: LucideIcons.fileText,
                color: DesignTokens.colorListIconDocument,
                title: '开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '邻接 Interconnect',
                  applicationVersion: installed?.version,
                  applicationLegalese: '媒体解码使用 LGPL 2.1 或更高版本许可的 FFmpeg。',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpdateStatus extends StatelessWidget {
  const _UpdateStatus({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 152),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _UpdatePrompt extends StatelessWidget {
  const _UpdatePrompt({required this.latest, required this.current});
  final AppRelease latest;
  final AppInfo current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: DesignTokens.componentUpdateDialogRingSize,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: DesignTokens.spacingXxs,
                  color: DesignTokens.colorDevicePanel,
                ),
              ),
              Positioned(
                top: 0,
                child: Icon(
                  Icons.circle,
                  size: DesignTokens.spacingXs,
                  color: DesignTokens.colorAccentBlue,
                ),
              ),
              Icon(
                AppIcons.download,
                size: DesignTokens.componentUpdateDialogGlyphSize,
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          '发现新版本',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          '${current.version}  →  ${latest.version}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (latest.bytes case final bytes?) ...[
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            '${(bytes / 1048576).toStringAsFixed(1)} MB',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    final notes = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('本次更新', style: theme.textTheme.titleMedium)),
            TextButton(
              onPressed: () => Navigator.pop(context, 'history'),
              child: const Text('查看更新记录'),
            ),
          ],
        ),
        for (final note in latest.notes)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
            child: Text(note, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
    final media = MediaQuery.of(context);
    final wide =
        media.size.height - media.viewInsets.vertical <
            DesignTokens.componentWorkspaceSplitHeight &&
        media.size.width - media.padding.horizontal >=
            DesignTokens.componentUpdateDialogWideWidth +
                2 * DesignTokens.spacingMd;
    Widget withActions(Widget content) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: SingleChildScrollView(child: content)),
        const SizedBox(height: DesignTokens.spacingMd),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(
              DesignTokens.componentAlertButtonHeight,
            ),
          ),
          onPressed: () => Navigator.pop(context, 'open'),
          child: const Text('前往发布渠道'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后'),
        ),
      ],
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      backgroundColor: theme.dialogTheme.backgroundColor,
      elevation: 0,
      constraints: BoxConstraints.tightFor(
        width: wide
            ? DesignTokens.componentUpdateDialogWideWidth
            : DesignTokens.componentAlertWidth,
      ),
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentAlertRounded),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(
          wide
              ? DesignTokens.componentUpdateDialogWidePadding
              : DesignTokens.spacingLg,
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignTokens.spacingLg,
                children: [
                  SizedBox(
                    width: DesignTokens.componentUpdateDialogSummaryWidth,
                    child: SingleChildScrollView(child: summary),
                  ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          start: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: DesignTokens.componentUpdateDialogWidePadding,
                        ),
                        child: withActions(notes),
                      ),
                    ),
                  ),
                ],
              )
            : withActions(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignTokens.spacingMd,
                  children: [summary, notes],
                ),
              ),
      ),
    );
  }
}
