import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:scrcpy_connect/services/adb_identity_validation.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class AdbIdentityPage extends HookWidget {
  const AdbIdentityPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final revision = useState(0);
    final busy = useState(false);
    final failure = useState<String?>(null);
    final notice = useState<String?>(null);
    final future = useMemoized(
      () => controller.request('identity.global.get'),
      [revision.value],
    );
    final result = useFuture(future);
    final data = result.data;
    const warning = '生成或导入新全局私钥后，使用全局私钥的连接将断开，需要在手机上重新授权。使用设备专用私钥的设备不受影响。';
    Future<void> change(String command, [String? pem]) async {
      busy.value = true;
      failure.value = null;
      notice.value = null;
      try {
        final response = await controller.request(command, {
          'privateKeyPem': ?pem,
        });
        if (value(response, 'fingerprint').isEmpty) {
          throw const RequestFailure(
            'identity_result_invalid',
            '无法核验私钥更新结果，请重新读取。',
          );
        }
        await controller.refreshDevices();
        if (!context.mounted) return;
        notice.value = '私钥已更新，请在手机上重新授权。';
        revision.value++;
      } catch (error) {
        if (context.mounted) failure.value = '$error';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PageFrame(
      title: 'ADB 私钥',
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('全局私钥', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: DesignTokens.spacingXs),
                  SelectableText(
                    value(
                      data ?? {},
                      'fingerprint',
                      result.connectionState == ConnectionState.done
                          ? '指纹未获取'
                          : '正在读取…',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(warning, style: Theme.of(context).textTheme.bodySmall),
            if (result.hasError) ...[
              StateNote('${result.error}'),
              TextButton(
                onPressed: busy.value ? null : () => revision.value++,
                child: const Text('重新读取'),
              ),
            ],
            if (failure.value != null) StateNote(failure.value!),
            if (notice.value != null) StateNote(notice.value!),
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton(
              onPressed: busy.value
                  ? null
                  : () async {
                      final pem = await showGlassDialog<String>(
                        context: context,
                        builder: (_) => const _PrivateKeyInput(),
                      );
                      if (pem == null || !context.mounted) return;
                      if (!await confirmConnectionChange(
                            context,
                            '导入 ADB 私钥？',
                            warning,
                            action: '导入并更换',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      await change('identity.global.import', pem);
                    },
              child: Text(busy.value ? '正在更新…' : '导入私钥'),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            OutlinedButton(
              onPressed: busy.value
                  ? null
                  : () async {
                      if (!await confirmConnectionChange(
                            context,
                            '重置全局 ADB 私钥？',
                            '将生成新的全局私钥。使用全局私钥的设备连接将断开，需在手机上重新授权；设备专用私钥不受影响。',
                            action: '重置密钥',
                            danger: true,
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      await change('identity.global.reset');
                    },
              child: const Text('重置密钥'),
            ),
          ],
        ),
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

    return ConnectionContent(
      child: GlassAlertDialog(
        title: const Text('导入私钥'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PEM 格式 · RSA 2048',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              TextFormField(
                controller: pem,
                enabled: !loading.value,
                onChanged: (_) => fileError.value = null,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                decoration: InputDecoration(
                  labelText: 'PEM 私钥',
                  errorText: fileError.value,
                ),
                validator: validateAdbPrivateKeyPem,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: loading.value ? null : pickFile,
                  child: Text(loading.value ? '正在读取…' : '从文件选择'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: loading.value
                ? null
                : () {
                    if (key.currentState!.validate()) {
                      Navigator.pop(
                        context,
                        normalizeAdbPrivateKeyPem(pem.text),
                      );
                    }
                  },
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }
}
