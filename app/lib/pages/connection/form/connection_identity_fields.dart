import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/adb_identity_validation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// The identity input belongs to the uncommitted connection attempt. Picking a
/// file only fills this field; the current method's action submits it later.
class ConnectionIdentityFields extends HookWidget {
  const ConnectionIdentityFields({
    super.key,
    required this.controller,
    required this.pem,
    required this.scope,
    required this.onScopeChanged,
    required this.onDraftChanged,
    required this.onFileLoadingChanged,
    this.deviceId,
    this.enabled = true,
  });

  final AppController controller;
  final TextEditingController pem;
  final String scope;
  final ValueChanged<String> onScopeChanged;
  final VoidCallback onDraftChanged;
  final ValueChanged<bool> onFileLoadingChanged;
  final String? deviceId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final loadingFile = useState(false);
    final fileError = useState<String?>(null);
    final bound = deviceId != null;
    final identityFuture = useMemoized(
      () => bound
          ? controller.request('identity.device.get', {'deviceId': deviceId})
          : Future<Json>.value({}),
      [controller, deviceId],
    );
    final identity = useFuture(identityFuture, preserveState: false);
    Future<void> pickFile() async {
      if (loadingFile.value) return;
      loadingFile.value = true;
      onFileLoadingChanged(true);
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
        onDraftChanged();
      } on AdbPrivateKeyFileFailure catch (failure) {
        if (context.mounted) fileError.value = failure.message;
      } catch (_) {
        if (context.mounted) fileError.value = '无法读取所选文件，请重新选择。';
      } finally {
        if (context.mounted) {
          loadingFile.value = false;
          onFileLoadingChanged(false);
        }
      }
    }

    final boundScope = value(identity.data ?? {}, 'scope');
    final fingerprint = value(identity.data ?? {}, 'fingerprint');
    final boundLabel = switch (boundScope) {
      'device' => '设备专属私钥',
      'global' => '全局私钥',
      _ => identity.connectionState != ConnectionState.done ? '正在读取…' : '来源未获取',
    };
    final source = ConnectSelectionField<String>(
      label: 'ADB 私钥',
      value: bound ? boundScope : scope,
      readOnly: bound,
      icon: const Icon(LucideIcons.chevronDown, size: 16),
      items: bound
          ? [DropdownMenuItem(value: boundScope, child: Text(boundLabel))]
          : const [
              DropdownMenuItem(value: 'global', child: Text('全局私钥')),
              DropdownMenuItem(value: 'device', child: Text('设备专属私钥')),
            ],
      onChanged: !bound && enabled && !loadingFile.value
          ? (next) {
              if (next != null) onScopeChanged(next);
            }
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bound) ...[
          if (fingerprint.isNotEmpty)
            GlassTooltip(message: fingerprint, child: source)
          else
            source,
          if (identity.hasError) StateNote('${identity.error}'),
        ] else ...[
          source,
          if (scope == 'device') ...[
            const SizedBox(height: DesignTokens.spacingMd),
            TextFormField(
              controller: pem,
              enabled: enabled && !loadingFile.value,
              minLines: 4,
              maxLines: 8,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              validator: validateAdbPrivateKeyPem,
              onChanged: (_) {
                fileError.value = null;
                onDraftChanged();
              },
              decoration: InputDecoration(
                labelText: 'PEM 私钥',
                errorText: fileError.value,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: enabled && !loadingFile.value ? pickFile : null,
                child: Text(loadingFile.value ? '正在读取…' : '从文件选择'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
