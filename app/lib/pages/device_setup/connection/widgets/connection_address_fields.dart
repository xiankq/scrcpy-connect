import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/input_field.dart';

/// 地址与端口并排所需的最小宽度（按 1 倍字号计）；不足时改为纵排（Ardot 2:2468）。
const _sideBySideMinWidth = 275.0;

/// 连接表单字段（Ardot 2:828、2:927）：地址与端口 2:1 并排、间距 12，字段之间 16，
/// 字段下方为 `subheadline` 次要色说明。
class ConnectionAddressFields extends HookWidget {
  const ConnectionAddressFields({
    super.key,
    required this.address,
    required this.port,
    required this.pairingCode,
    required this.pairing,
    required this.legacyTcp,
    required this.enabled,
    required this.onAddressChanged,
  });

  final TextEditingController address;
  final TextEditingController port;
  final TextEditingController pairingCode;
  final bool pairing;
  final bool legacyTcp;
  final bool enabled;
  final ValueChanged<String> onAddressChanged;

  @override
  Widget build(BuildContext context) {
    final focus = (
      address: useFocusNode(),
      port: useFocusNode(),
      pairingCode: useFocusNode(),
    );
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final addressField = AppTextField(
      focusNode: focus.address,
      controller: address,
      label: pairing ? '手机地址' : 'IP 地址或主机名',
      validator: validateAddress,
      enabled: enabled,
      hintText: '192.168.1.8',
      autocorrect: false,
      onChanged: onAddressChanged,
    );
    final portField = AppTextField(
      focusNode: focus.port,
      controller: port,
      label: pairing ? '配对端口' : '连接端口',
      validator: validatePort,
      enabled: enabled,
      keyboardType: TextInputType.number,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            return constraints.maxWidth < _sideBySideMinWidth * scale
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      addressField,
                      const SizedBox(height: DesignTokens.spacingLg),
                      portField,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: addressField),
                      const SizedBox(width: DesignTokens.spacingMd),
                      Expanded(child: portField),
                    ],
                  );
          },
        ),
        if (pairing) ...[
          const SizedBox(height: DesignTokens.spacingLg),
          AppTextField(
            focusNode: focus.pairingCode,
            controller: pairingCode,
            label: '六位配对码',
            enabled: enabled,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : '请输入手机上显示的 6 位配对码',
          ),
        ],
        const SizedBox(height: DesignTokens.spacingLg),
        Text(
          pairing
              ? '在手机的无线调试中选择「使用配对码配对」。'
              : legacyTcp
              ? '仅连接已授权的手机。请输入当前连接地址，并在可信网络使用。'
              : '使用手机无线调试主页面的连接地址和端口。',
          style: type.subheadline.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
