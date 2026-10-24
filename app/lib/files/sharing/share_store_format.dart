import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 与旧 Rust 的带类型、长度前缀 SHA-256 字节格式保持一致。
String shareRequestFingerprint(Object? value) {
  final output = BytesBuilder(copy: false);
  void length(int n) =>
      output.add((ByteData(8)..setUint64(0, n)).buffer.asUint8List());
  void sized(List<int> bytes) {
    length(bytes.length);
    output.add(bytes);
  }

  int compare(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    for (var i = 0; i < x.length && i < y.length; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return x.length.compareTo(y.length);
  }

  void visit(Object? v) {
    switch (v) {
      case null:
        output.addByte(0);
      case bool():
        output.add([1, v ? 1 : 0]);
      case num():
        if (!v.isFinite) throw const FormatException('分享请求不能包含非有限数。');
        output.addByte(2);
        sized(utf8.encode(v is double ? _rustDouble(v) : v.toString()));
      case String():
        output.addByte(3);
        sized(utf8.encode(v));
      case List():
        output.addByte(4);
        length(v.length);
        for (final child in v) {
          visit(child);
        }
      case Map():
        if (v.keys.any((key) => key is! String)) {
          throw const FormatException('分享请求的键必须是文字。');
        }
        output.addByte(5);
        length(v.length);
        final keys = v.keys.cast<String>().toList()..sort(compare);
        for (final key in keys) {
          sized(utf8.encode(key));
          visit(v[key]);
        }
      default:
        throw const FormatException('分享请求不是 JSON 数据。');
    }
  }

  visit(value);
  return 'sha256:${sha256.convert(output.takeBytes())}';
}

String _rustDouble(double value) {
  // Dart 与 serde_json 的 zmij 都提供最短可回读有效数字；按其指数区间重新排版。
  final sign = value.isNegative ? '-' : '';
  if (value == 0) return '${sign}0.0';
  final parts = value.abs().toString().split('e');
  final decimal = parts[0].indexOf('.');
  var position =
      (decimal < 0 ? parts[0].length : decimal) +
      (parts.length == 1 ? 0 : int.parse(parts[1]));
  var digits = parts[0].replaceAll('.', '');
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
    position--;
  }
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  if (position > 0 && position <= 16) {
    if (position >= digits.length) {
      return '$sign$digits${'0' * (position - digits.length)}.0';
    }
    return '$sign${digits.substring(0, position)}.${digits.substring(position)}';
  }
  if (position > -5 && position <= 0) {
    return '${sign}0.${'0' * -position}$digits';
  }
  return '$sign${digits[0]}${digits.length == 1 ? '' : '.${digits.substring(1)}'}e${position > 0 ? '+' : ''}${position - 1}';
}

/// java.util.Properties 以 ISO-8859-1 字节及 UTF-16 转义保存旧日志。
Map<String, String> readShareProperties(List<int> bytes) {
  final result = <String, String>{};
  var logical = '';
  String unescape(String input) {
    final units = <int>[];
    for (var i = 0; i < input.length; i++) {
      var unit = input.codeUnitAt(i);
      if (unit == 92) {
        if (++i >= input.length) throw const FormatException('旧分享日志转义未完成。');
        unit = input.codeUnitAt(i);
        if (unit == 117) {
          if (i + 4 >= input.length) {
            throw const FormatException('旧分享日志 Unicode 未完成。');
          }
          unit = int.parse(input.substring(i + 1, i + 5), radix: 16);
          i += 4;
        } else {
          unit = switch (unit) {
            110 => 10,
            114 => 13,
            116 => 9,
            102 => 12,
            _ => unit,
          };
        }
      }
      units.add(unit);
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('旧分享日志代理对无效。');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('旧分享日志代理对无效。');
      }
    }
    return String.fromCharCodes(units);
  }

  for (final physical in const LineSplitter().convert(latin1.decode(bytes))) {
    final line = physical.replaceFirst(RegExp(r'^[ \t\f]*'), '');
    if (logical.isEmpty && (line.startsWith('#') || line.startsWith('!'))) {
      continue;
    }
    logical += line;
    final trailing = RegExp(r'\\+$').firstMatch(logical)?.group(0)?.length ?? 0;
    if (trailing.isOdd) {
      logical = logical.substring(0, logical.length - 1);
      continue;
    }
    if (logical.isNotEmpty) {
      var escaped = false, split = logical.length;
      for (var i = 0; i < logical.length; i++) {
        final c = logical[i];
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '=' || c == ':' || RegExp(r'\s').hasMatch(c)) {
          split = i;
          break;
        }
      }
      var rest = logical
          .substring(split)
          .replaceFirst(RegExp(r'^[ \t\f]*'), '');
      if (rest.startsWith('=') || rest.startsWith(':')) {
        rest = rest.substring(1);
      }
      rest = rest.replaceFirst(RegExp(r'^[ \t\f]*'), '');
      result[unescape(logical.substring(0, split))] = unescape(rest);
    }
    logical = '';
  }
  if (logical.isNotEmpty) throw const FormatException('旧分享日志未写完。');
  return result;
}
