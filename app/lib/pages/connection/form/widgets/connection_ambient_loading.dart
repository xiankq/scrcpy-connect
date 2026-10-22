import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

class ConnectionAmbientLoading extends StatelessWidget {
  const ConnectionAmbientLoading({
    super.key,
    required this.cancelling,
    required this.onCancel,
  });

  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AmbientLoadingField(
      semanticsLabel: '正在连接设备',
      footer: SizedBox(
        width: double.infinity,
        child: GlassSurfaceGroup(
          child: Glass(
            radius: DesignTokens.roundedFull,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  DesignTokens.componentButtonSecondaryHeight,
                ),
              ),
              onPressed: cancelling ? null : onCancel,
              icon: Icon(
                cancelling ? LucideIcons.loaderCircle : LucideIcons.x,
                size: DesignTokens.componentIconActionSize,
              ),
              label: Text(cancelling ? '正在取消…' : '取消本次尝试'),
            ),
          ),
        ),
      ),
    );
  }
}
