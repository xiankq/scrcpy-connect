import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/file_browser.dart';

IconData fileKindIcon(FileKind kind) => switch (kind) {
  FileKind.documents => LucideIcons.fileText,
  FileKind.images => LucideIcons.image,
  FileKind.videos => LucideIcons.video,
  FileKind.audio => LucideIcons.audioLines,
  FileKind.archives => LucideIcons.package,
  FileKind.other => LucideIcons.file,
};

Color fileKindColor(FileKind kind) => switch (kind) {
  FileKind.documents || FileKind.archives => DesignTokens.colorListIconAmber,
  FileKind.images || FileKind.videos => DesignTokens.colorListIconPurple,
  FileKind.audio => DesignTokens.colorListIconSlate,
  FileKind.other => DesignTokens.colorListIconSlate,
};
