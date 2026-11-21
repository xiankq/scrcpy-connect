import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_validation.dart';
import 'package:scrcpy_connect/core/identity/adb_private_key_file_failure.dart';
import 'package:scrcpy_connect/core/identity/models/authorization_identity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/identity/identity_management_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

import '../widgets/settings_row.dart';

class AdbIdentityPage extends HookConsumerWidget {
  const AdbIdentityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(identityManagementProvider);
    bool ownsScope() =>
        context.mounted &&
        identical(ref.read(identityManagementProvider), source);
    final revision = useValueNotifier<int>(0, [source]);
    useValueListenable(revision);
    final busy = useValueNotifier<bool>(false, [source]);
    useValueListenable(busy);
    final failure = useValueNotifier<String?>(null, [source]);
    useValueListenable(failure);
    final notice = useValueNotifier<String?>(null, [source]);
    useValueListenable(notice);
    final future = useMemoized(source.readGlobal, [source, revision.value]);
    final result = useFuture(future, preserveState: false);
    final data = result.data;
    const warning = '生成或导入新全局私钥后，使用全局私钥的连接将断开，需要在手机上重新授权。使用设备专用私钥的设备不受影响。';
    Future<void> change(Future<AuthorizationIdentity> Function() update) async {
      if (!ownsScope() || busy.value) return;
      busy.value = true;
      failure.value = null;
      notice.value = null;
      try {
        final response = await update();
        if (response.fingerprint.isEmpty) {
          throw const RequestFailure(
            'identity_result_invalid',
            '无法核验私钥更新结果，请重新读取。',
          );
        }
        if (!ownsScope()) return;
        await ref.read(deviceListProvider.notifier).refresh();
        if (!context.mounted || !ownsScope()) return;
        notice.value = '私钥已更新，请在手机上重新授权。';
        revision.value++;
      } catch (error) {
        if (ownsScope()) failure.value = '$error';
      } finally {
        if (ownsScope()) busy.value = false;
      }
    }

    Future<void> importIdentity() async {
      final pem = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _PrivateKeyInput()),
      );
      if (pem == null || !context.mounted || !ownsScope()) return;
      if (!await confirmConnectionChange(
            context,
            '将中断现有连接',
            warning,
            action: '导入并更换',
          ) ||
          !context.mounted ||
          !ownsScope()) {
        return;
      }
      await change(() => source.importGlobal(pem));
    }

    Future<void> resetIdentity() async {
      if (!await confirmConnectionChange(
            context,
            '重置身份？',
            warning,
            action: '重置身份',
            danger: true,
          ) ||
          !context.mounted ||
          !ownsScope()) {
        return;
      }
      await change(source.resetGlobal);
    }

    final fingerprint = data?.fingerprint;
    return PageFrame(
      title: '授权密钥',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                compact: true,
                icon: LucideIcons.fingerprint,
                color: DesignTokens.colorListIconSlate,
                title: '本机指纹',
                value: fingerprint == null
                    ? (result.connectionState == ConnectionState.done
                          ? '未读取'
                          : '正在读取…')
                    : fingerprint.length > 12
                    ? '${fingerprint.substring(0, 5)}:…:${fingerprint.substring(fingerprint.length - 2)}'
                    : fingerprint,
                onTap: fingerprint == null
                    ? null
                    : () => showAppDialog<void>(
                        context: context,
                        title: const Text('本机指纹'),
                        content: SelectableText(fingerprint),
                        actions: [
                          Builder(
                            builder: (context) => TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('完成'),
                            ),
                          ),
                        ],
                      ),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.keyRound,
                color: DesignTokens.colorListIconBlue,
                title: '导入身份',
                onTap: busy.value ? null : importIdentity,
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.rotateCcw,
                color: DesignTokens.colorListIconCoral,
                title: '重置身份',
                destructive: true,
                onTap: busy.value ? null : resetIdentity,
              ),
            ],
          ),
          if (result.hasError) StateNote('${result.error}'),
          if (failure.value case final error?) StateNote(error),
          if (notice.value case final message?) StateNote(message),
          Center(
            child: TextButton(
              onPressed: busy.value ? null : () => revision.value++,
              child: Text(busy.value ? '正在更新…' : '更新指纹'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateKeyInput extends HookWidget {
  const _PrivateKeyInput();
  @override
  Widget build(BuildContext context) {
    final key = useMemoized(GlobalKey<FormState>.new);
    final pem = useTextEditingController();
    final loading = useState(false);
    final fileError = useState<String?>(null);
    Future<void> pickFile() async {
      if (loading.value) return;
      loading.value = true;
      try {
        final file = await FilePicker.pickFile(dialogTitle: '选择 PEM 私钥文件');
        if (!context.mounted || file == null) return;
        if ((file.lengthSync() ?? 0) > maxAdbPrivateKeyBytes) {
          throw const AdbPrivateKeyFileFailure('私钥文件不能超过 32 KiB。');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in file.readAsByteStream()) {
          if (!context.mounted) return;
          if (bytes.length + chunk.length > maxAdbPrivateKeyBytes) {
            throw const AdbPrivateKeyFileFailure('私钥文件不能超过 32 KiB。');
          }
          bytes.add(chunk);
        }
        final text = decodeAdbPrivateKeyFile(bytes.takeBytes());
        if (!context.mounted) return;
        pem.text = text;
        fileError.value = null;
        key.currentState!.validate();
      } on AdbPrivateKeyFileFailure catch (error) {
        if (context.mounted) fileError.value = error.message;
      } catch (_) {
        if (context.mounted) fileError.value = '无法读取所选文件，请重新选择。';
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return PageFrame(
      title: '导入身份',
      onBack: () => Navigator.pop(context),
      bottomGlass: false,
      bottom: FilledButton(
        onPressed: loading.value
            ? null
            : () {
                if (key.currentState!.validate()) {
                  Navigator.pop(context, normalizeAdbPrivateKeyPem(pem.text));
                }
              },
        child: const Text('核对替换影响'),
      ),
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            Form(
              key: key,
              child: TextFormField(
                controller: pem,
                enabled: !loading.value,
                onChanged: (_) => fileError.value = null,
                minLines: 5,
                maxLines: 10,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                decoration: InputDecoration(
                  labelText: '私钥文本',
                  hintText: '粘贴 RSA 私钥',
                  alignLabelWithHint: true,
                  errorText: fileError.value,
                ),
                validator: validateAdbPrivateKeyPem,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: loading.value ? null : pickFile,
                icon: const Icon(LucideIcons.folderOpen),
                label: Text(loading.value ? '正在读取…' : '选取文件'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
