import 'package:flutter/material.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/documents/document_export_form.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class DocumentExportPage extends StatelessWidget {
  const DocumentExportPage({
    super.key,
    required this.controller,
    required this.localPath,
    required this.name,
    required this.kind,
    this.transferId,
    this.partial = false,
    this.sourceLabel = '被控设备',
  });
  final AppNotifier controller;
  final String localPath;
  final String name;
  final String kind;
  final String? transferId;
  final bool partial;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: !supportsSystemDocumentSave ? '系统分享原文件' : '保存到系统位置',
    child: DocumentExportForm(
      controller: controller,
      localPath: localPath,
      name: name,
      kind: kind,
      transferId: transferId,
      partial: partial,
      sourceLabel: sourceLabel,
    ),
  );
}
