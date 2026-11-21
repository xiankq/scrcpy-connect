import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_connect/core/platform/models/app_info.dart';

final class AppRelease {
  const AppRelease({
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.notes,
    required this.url,
    this.bytes,
  });

  final String version;
  final int build;
  final DateTime publishedAt;
  final List<String> notes;
  final Uri url;
  final int? bytes;

  bool matches(AppInfo installed) =>
      installed.version == version &&
      int.tryParse(installed.buildNumber) == build;

  int compareTo(AppRelease other) =>
      _compare(version, build, other.version, other.build);

  bool isNewerThan(AppInfo installed) =>
      _compare(
        version,
        build,
        installed.version,
        int.tryParse(installed.buildNumber) ?? 0,
      ) >
      0;

  static final _stableVersion = RegExp(r'^\d+\.\d+\.\d+$');

  static int _compare(
    String first,
    int firstBuild,
    String second,
    int secondBuild,
  ) {
    final a = first.split('.');
    final b = second.split('.');
    for (var index = 0; index < a.length; index++) {
      final difference = int.parse(a[index]).compareTo(int.parse(b[index]));
      if (difference != 0) return difference;
    }
    return firstBuild.compareTo(secondBuild);
  }

  factory AppRelease.fromJson(Map<String, Object?> data) {
    final version = data['version'];
    final build = data['build'];
    final date = data['publishedAt'];
    final notes = data['notes'];
    final url = data['url'];
    final bytes = data['bytes'];
    if (version is! String ||
        !_stableVersion.hasMatch(version) ||
        build is! int ||
        build < 0 ||
        date is! String ||
        DateTime.tryParse(date) == null ||
        notes is! List ||
        !notes.every((note) => note is String) ||
        url is! String ||
        bytes != null && (bytes is! int || bytes <= 0)) {
      throw const FormatException('版本发布记录格式不正确。');
    }
    return AppRelease(
      version: version,
      build: build,
      publishedAt: DateTime.parse(date),
      notes: List.unmodifiable(notes.cast<String>()),
      url: _httpsUrl(Uri.parse(url)),
      bytes: bytes as int?,
    );
  }
}

Uri _httpsUrl(Uri uri) {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const FormatException('更新渠道需要有效的 HTTPS 地址。');
  }
  return uri;
}

Future<List<AppRelease>> readAppReleases(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(_httpsUrl(url));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('发布渠道暂时无法提供更新记录。');
    }
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    final records = (jsonDecode(body) as List).cast<Map<String, Object?>>();
    return records.map(AppRelease.fromJson).toList(growable: false)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  } finally {
    client.close(force: true);
  }
}
