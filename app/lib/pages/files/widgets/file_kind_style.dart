import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/models/file_kind.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

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
