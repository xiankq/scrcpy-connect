import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/models/file_kind.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 文件夹的格式图形与格式色（Ardot 文件格式 37:1032「文件夹」）。
const folderKindIcon = LucideIcons.folder;
const folderKindColor = DesignTokens.colorAccentAmber;

/// 文件格式图形（Ardot 文件格式 37:1032）。
IconData fileKindIcon(FileKind kind) => switch (kind) {
  FileKind.documents => LucideIcons.fileText,
  FileKind.images => LucideIcons.image,
  FileKind.videos => LucideIcons.film,
  FileKind.audio => LucideIcons.music,
  FileKind.archives => LucideIcons.fileArchive,
  FileKind.other => LucideIcons.file,
};

/// design.md「功能色」：文件夹和压缩包 amber，PDF red，文档 indigo，
/// 图片和视频 purple，音频 teal，其他 gray。
Color fileKindColor(FileKind kind, {String? name, String? mime}) =>
    switch (kind) {
      FileKind.documents
          when mime == 'application/pdf' ||
              name?.toLowerCase().endsWith('.pdf') == true =>
        DesignTokens.colorAccentRed,
      FileKind.documents => DesignTokens.colorAccentIndigo,
      FileKind.archives => DesignTokens.colorAccentAmber,
      FileKind.images || FileKind.videos => DesignTokens.colorAccentPurple,
      FileKind.audio => DesignTokens.colorAccentTeal,
      FileKind.other => DesignTokens.colorAccentGray,
    };
