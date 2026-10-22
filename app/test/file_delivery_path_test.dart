import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/file_delivery_path.dart';

void main() {
  Future<void> pumpPath(
    WidgetTester tester, {
    required String sourceLabel,
    required bool staged,
    required FileDeliveryMilestone systemState,
    String systemLabel = '系统副本',
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ConnectTokens.theme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 338,
            child: FileDeliveryPath(
              sourceLabel: sourceLabel,
              systemLabel: systemLabel,
              staged: staged,
              systemState: systemState,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('preparation names the real source, staging and system copy', (
    tester,
  ) async {
    await pumpPath(
      tester,
      sourceLabel: '我的手机',
      staged: false,
      systemState: FileDeliveryMilestone.pending,
    );
    expect(find.text('我的手机'), findsOneWidget);
    expect(find.text('本机暂存'), findsOneWidget);
    expect(find.text('系统副本'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('系统副本')).style?.color,
      isNot(ConnectTokens.mint),
    );
  });

  testWidgets('saved state marks the system milestone complete', (
    tester,
  ) async {
    await pumpPath(
      tester,
      sourceLabel: '我的手机',
      staged: true,
      systemState: FileDeliveryMilestone.complete,
    );
    final colors = ConnectTokens.theme(Brightness.light).colorScheme;
    expect(
      tester.widget<Text>(find.text('系统副本')).style?.color,
      colors.onSurface,
    );
    expect(find.byIcon(LucideIcons.fileOutput), findsOneWidget);
  });

  testWidgets('unknown state shows the attention icon and danger label', (
    tester,
  ) async {
    await pumpPath(
      tester,
      sourceLabel: '我的手机',
      staged: true,
      systemState: FileDeliveryMilestone.attention,
    );
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
    final colors = ConnectTokens.theme(Brightness.light).colorScheme;
    expect(tester.widget<Text>(find.text('系统副本')).style?.color, colors.error);
  });

  testWidgets('share uses the receiving app as the third milestone', (
    tester,
  ) async {
    await pumpPath(
      tester,
      sourceLabel: '我的手机',
      staged: true,
      systemState: FileDeliveryMilestone.pending,
      systemLabel: '接收应用',
    );
    expect(find.text('接收应用'), findsOneWidget);
    expect(find.text('系统副本'), findsNothing);
    expect(find.byIcon(LucideIcons.fileOutput), findsOneWidget);
  });
}
