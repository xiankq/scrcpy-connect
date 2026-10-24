import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/files/catalog/file_type_policy.dart';

void main() {
  test(
    'classification uses known MIME before names and generic MIME falls back',
    () {
      expect(
        FileTypePolicy.kind(
          name: 'photo.jpg',
          mime: 'APPLICATION/PDF; charset=utf-8',
        ),
        FileKind.documents,
      );
      expect(
        FileTypePolicy.kind(
          name: 'report.json',
          mime: 'application/octet-stream',
        ),
        FileKind.documents,
      );
      expect(
        FileTypePolicy.kind(name: 'unknown.bin', mime: 'image/png'),
        FileKind.images,
      );
      expect(FileTypePolicy.kind(name: 'photo.JPG'), FileKind.images);
      expect(FileTypePolicy.kind(name: 'clip.MP4'), FileKind.videos);
      expect(FileTypePolicy.kind(name: 'song.FLAC'), FileKind.audio);
      expect(FileTypePolicy.kind(name: 'archive.xz'), FileKind.archives);
      expect(
        FileTypePolicy.kind(name: 'unknown.bin', mime: 'application/x-unknown'),
        FileKind.other,
      );
      expect(FileTypePolicy.mime('/path/report.json'), 'application/json');
    },
  );
}
