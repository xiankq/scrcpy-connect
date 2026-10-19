import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Converts a production packet archive into one preloaded native replay bundle.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('bundle', help: 'Optional MDKP output path.')
    ..addOption('defines', help: 'Optional dart-define-from-file JSON path.')
    ..addFlag(
      'finite-clusters',
      negatable: false,
      help: 'Experiment: replace only Cluster unknown sizes with actual sizes.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args['help'] == true || args.rest.length != 1) {
    stdout.writeln(
      'Usage: dart run tool/benchmark/native_input_fixture.dart '
      '<archive-directory> [--bundle output.mdkp] '
      '[--defines defines.json]\n'
      '${parser.usage}',
    );
    if (args['help'] != true) exitCode = 64;
    return;
  }
  final directory = Directory(args.rest.first).absolute;
  final archive = jsonDecode(
    await File(p.join(directory.path, 'archive.json')).readAsString(),
  );
  if (archive is! Map<String, dynamic> || archive['complete'] != true) {
    throw const FormatException('Expected a complete packet archive.');
  }
  final frames = archive['frames'];
  if (frames is! List || frames.isEmpty || frames.length > 0xfffffffe) {
    throw const FormatException('Invalid archive frame count.');
  }
  final pts = <int>[];
  for (final frame in frames) {
    final timestamp = frame is Map ? frame['ptsUs'] : null;
    if (timestamp is! int ||
        timestamp < 0 ||
        (pts.isEmpty ? timestamp != 0 : timestamp < pts.last)) {
      throw const FormatException('PTS must start at zero and never decrease.');
    }
    pts.add(timestamp);
  }
  final capture = await File(p.join(directory.path, 'capture.mkv'))
      .readAsBytes();
  if (archive['bytes'] != capture.length) {
    throw const FormatException('Archive byte count does not match capture.');
  }
  final chunks = _splitCapture(capture, pts);
  if (args['finite-clusters'] == true) {
    for (var i = 1; i < chunks.length; i++) {
      final source = chunks[i];
      final element = _element(source, 0, source.length);
      if (element.id != _cluster || element.end != null) {
        throw const FormatException('Expected an unknown-sized Cluster');
      }
      final width = element.data - 4;
      final size = source.length - element.data;
      if (width < 1 || width > 8 || size >= (1 << (width * 7)) - 1) {
        throw const FormatException('Cluster size does not fit existing VINT');
      }
      final finite = Uint8List.fromList(source);
      var encoded = (1 << (width * 7)) | size;
      for (var offset = element.data - 1; offset >= 4; offset--) {
        finite[offset] = encoded & 255;
        encoded >>= 8;
      }
      chunks[i] = finite;
    }
  }
  final output = BytesBuilder(copy: false)..add(ascii.encode('MDKP'));
  final count = ByteData(4)..setUint32(0, chunks.length, Endian.big);
  output.add(count.buffer.asUint8List());
  for (var index = 0; index < chunks.length; index++) {
    final chunk = chunks[index];
    if (chunk.isEmpty || chunk.length > 0xffffffff) {
      throw const FormatException('Invalid MDKP chunk length.');
    }
    final prefix = ByteData(12)
      ..setUint64(0, index == 0 ? 0 : pts[index - 1], Endian.big)
      ..setUint32(8, chunk.length, Endian.big);
    output
      ..add(prefix.buffer.asUint8List())
      ..add(chunk);
  }
  final bundle = output.takeBytes();
  final temporary = args['defines'] == null || args['bundle'] == null
      ? await Directory.systemTemp.createTemp('connect-mdk-input-fixture-')
      : null;
  final bundlePath =
      args['bundle'] as String? ?? p.join(temporary!.path, 'fixture.mdkp');
  final definesPath =
      args['defines'] as String? ??
      p.join(temporary!.path, 'native_input_fixture_defines.json');
  final defines = <String, Object>{
    'nativeInputFixtureSha256': sha256.convert(bundle).toString(),
    'nativeInputCaptureSha256': sha256.convert(capture).toString(),
    'nativeInputFixtureChunkCount': chunks.length,
    'nativeInputFixtureFrameCount': pts.length,
    'nativeInputFixtureDurationUs': pts.last,
    'nativeInputFixtureBytes': bundle.length,
    'nativeInputCaptureBytes': capture.length,
    'nativeInputClusterSizing': args['finite-clusters'] == true
        ? 'finite'
        : 'unknown',
    'nativeInputReplaySha256': sha256
        .convert(chunks.expand((c) => c).toList())
        .toString(),
  };
  // create(exclusive:true) refuses to replace previous evidence or source files.
  final bundleFile = File(bundlePath);
  final definesFile = File(definesPath);
  await bundleFile.create(exclusive: true);
  await definesFile.create(exclusive: true);
  await bundleFile.writeAsBytes(bundle, flush: true);
  await definesFile.writeAsString(jsonEncode(defines), flush: true);
  stdout.writeln(
    jsonEncode({
      'defines': definesFile.absolute.path,
      'bundle': bundleFile.absolute.path,
      'sha256': sha256.convert(bundle).toString(),
      'chunks': chunks.length,
      'frames': pts.length,
      'durationUs': pts.last,
      'bytes': bundle.length,
    }),
  );
}

const _ebml = 0x1a45dfa3;
const _segment = 0x18538067;
const _info = 0x1549a966;
const _tracks = 0x1654ae6b;
const _cluster = 0x1f43b675;
const _timestamp = 0xe7;
const _simpleBlock = 0xa3;
const _timestampScale = 0x2ad7b1;

final class _Element {
  const _Element(this.id, this.start, this.data, this.end);
  final int id, start, data;
  final int? end;
}

// Read element identifiers and sizes at structural boundaries. Unknown sizes
// are accepted only for the production Segment and Cluster master elements.
_Element _element(Uint8List bytes, int offset, int limit) {
  final start = offset;
  (int, int) vint(bool identifier) {
    if (offset >= limit || bytes[offset] == 0) {
      throw const FormatException('Truncated or invalid EBML VINT.');
    }
    var mask = 0x80;
    var width = 1;
    while ((bytes[offset] & mask) == 0) {
      mask >>= 1;
      width++;
    }
    if (width > (identifier ? 4 : 8) || offset + width > limit) {
      throw const FormatException('Invalid EBML VINT width.');
    }
    var value = bytes[offset] & (identifier ? 0xff : mask - 1);
    for (var index = 1; index < width; index++) {
      value = (value << 8) | bytes[offset + index];
    }
    offset += width;
    return (value, width);
  }

  final (id, _) = vint(true);
  final (size, width) = vint(false);
  final unknown = size == (1 << (width * 7)) - 1;
  if (!unknown && size > limit - offset) {
    throw const FormatException('EBML element exceeds its parent.');
  }
  return _Element(id, start, offset, unknown ? null : offset + size);
}

int _unsigned(Uint8List bytes, _Element element) {
  final end = element.end;
  if (end == null || end <= element.data || end - element.data > 8) {
    throw const FormatException('Invalid EBML unsigned integer.');
  }
  var value = 0;
  for (var index = element.data; index < end; index++) {
    value = (value << 8) | bytes[index];
  }
  if (value < 0) {
    throw const FormatException('EBML integer exceeds signed u64.');
  }
  return value;
}

List<Uint8List> _splitCapture(Uint8List bytes, List<int> pts) {
  final ebml = _element(bytes, 0, bytes.length);
  if (ebml.id != _ebml || ebml.end == null) {
    throw const FormatException('Expected a sized EBML header.');
  }
  final segment = _element(bytes, ebml.end!, bytes.length);
  if (segment.id != _segment ||
      (segment.end != null && segment.end != bytes.length)) {
    throw const FormatException('Expected one complete Matroska Segment.');
  }
  final limit = segment.end ?? bytes.length;
  var cursor = segment.data;
  var infoSeen = false, tracksSeen = false;
  final chunks = <Uint8List>[];
  while (cursor < limit) {
    final element = _element(bytes, cursor, limit);
    if (element.id == _cluster) {
      if (!infoSeen || !tracksSeen) {
        throw const FormatException('Cluster precedes Info or Tracks.');
      }
      if (chunks.isEmpty) chunks.add(Uint8List.sublistView(bytes, 0, cursor));
      final index = chunks.length - 1;
      if (index >= pts.length) {
        throw const FormatException('More Clusters than archive frames.');
      }
      var childCursor = element.data;
      final childLimit = element.end ?? limit;
      int? timestamp;
      var blocks = 0;
      while (childCursor < childLimit) {
        final child = _element(bytes, childCursor, childLimit);
        if (element.end == null && child.id == _cluster) break;
        if (child.end == null) {
          throw const FormatException('Unknown-sized Cluster child.');
        }
        switch (child.id) {
          case _timestamp:
            if (timestamp != null) {
              throw const FormatException('Duplicate Cluster timestamp.');
            }
            timestamp = _unsigned(bytes, child);
          case _simpleBlock:
            blocks++;
            // The production mux uses track 1, relative timecode 0, no lacing.
            if (child.end! - child.data <= 4 ||
                bytes[child.data] != 0x81 ||
                bytes[child.data + 1] != 0 ||
                bytes[child.data + 2] != 0 ||
                (bytes[child.data + 3] & 6) != 0) {
              throw const FormatException('Unexpected production SimpleBlock.');
            }
          default:
            throw FormatException('Unexpected Cluster child: ${child.id}.');
        }
        childCursor = child.end!;
      }
      if (blocks != 1 || timestamp != pts[index]) {
        throw FormatException('Cluster $index does not match archive PTS.');
      }
      chunks.add(Uint8List.sublistView(bytes, cursor, childCursor));
      cursor = childCursor;
      continue;
    }
    if (chunks.isNotEmpty || element.end == null) {
      throw const FormatException(
        'Unexpected element outside production header.',
      );
    }
    if (element.id == _info && !infoSeen) {
      infoSeen = true;
      var childCursor = element.data;
      int? scale;
      while (childCursor < element.end!) {
        final child = _element(bytes, childCursor, element.end!);
        if (child.end == null) {
          throw const FormatException('Unknown-sized Info child.');
        }
        if (child.id == _timestampScale) {
          if (scale != null) {
            throw const FormatException('Duplicate TimestampScale.');
          }
          scale = _unsigned(bytes, child);
        }
        childCursor = child.end!;
      }
      if (scale != 1000) {
        throw const FormatException(
          'Expected microsecond Matroska timestamps.',
        );
      }
    } else if (element.id == _tracks && !tracksSeen) {
      tracksSeen = true;
    } else {
      throw FormatException('Unexpected production header ID: ${element.id}.');
    }
    cursor = element.end!;
  }
  if (chunks.length != pts.length + 1) {
    throw const FormatException('Cluster count does not match archive frames.');
  }
  return chunks;
}
