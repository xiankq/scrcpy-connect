import 'package:path/path.dart' as p;

enum FileKind { documents, images, videos, audio, archives, other }

/// 浏览、搜索与呈现共用的分类规则。
abstract final class FileTypePolicy {
  static String mime(String path) => switch (p.posix
      .extension(path)
      .toLowerCase()) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    '.heic' || '.heif' => 'image/heic',
    '.bmp' => 'image/bmp',
    '.mp4' || '.m4v' => 'video/mp4',
    '.mkv' => 'video/x-matroska',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.3gp' => 'video/3gpp',
    '.mp3' => 'audio/mpeg',
    '.m4a' || '.aac' => 'audio/aac',
    '.wav' => 'audio/wav',
    '.ogg' => 'audio/ogg',
    '.flac' => 'audio/flac',
    '.pdf' => 'application/pdf',
    '.txt' || '.md' || '.csv' || '.log' => 'text/plain',
    '.json' => 'application/json',
    '.xml' => 'application/xml',
    '.rtf' => 'application/rtf',
    '.doc' => 'application/msword',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls' => 'application/vnd.ms-excel',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.ppt' => 'application/vnd.ms-powerpoint',
    '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.odt' => 'application/vnd.oasis.opendocument.text',
    '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
    '.odp' => 'application/vnd.oasis.opendocument.presentation',
    '.zip' => 'application/zip',
    '.rar' => 'application/x-rar-compressed',
    '.7z' => 'application/x-7z-compressed',
    '.tar' => 'application/x-tar',
    '.gz' => 'application/gzip',
    '.bz2' => 'application/x-bzip2',
    '.xz' => 'application/x-xz',
    _ => 'application/octet-stream',
  };

  /// 优先采用已识别 MIME；通用或未知 MIME 按名称回退。
  static FileKind kind({required String name, String? mime}) =>
      _mimeKind(mime?.split(';').first.trim().toLowerCase() ?? '') ??
      _mimeKind(FileTypePolicy.mime(name)) ??
      FileKind.other;

  static FileKind? _mimeKind(String mime) {
    if (mime.startsWith('image/')) return FileKind.images;
    if (mime.startsWith('video/')) return FileKind.videos;
    if (mime.startsWith('audio/')) return FileKind.audio;
    if (mime.startsWith('text/') ||
        const {
          'application/pdf',
          'application/rtf',
          'application/document',
          'application/json',
          'application/xml',
        }.contains(mime) ||
        mime.contains('word') ||
        mime.contains('excel') ||
        mime.contains('spreadsheet') ||
        mime.contains('powerpoint') ||
        mime.contains('presentation') ||
        mime.startsWith('application/vnd.oasis.opendocument.')) {
      return FileKind.documents;
    }
    if (mime.contains('zip') ||
        mime.contains('compressed') ||
        mime.contains('archive') ||
        mime.contains('tar') ||
        mime.contains('gzip') ||
        mime == 'application/x-xz') {
      return FileKind.archives;
    }
    return null;
  }
}
