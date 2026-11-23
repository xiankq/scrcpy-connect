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
    // GitHub 下载入口会重定向到实际附件。每一跳仍必须是 HTTPS。
    var destination = _httpsUrl(url);
    HttpClientResponse response;
    var redirects = 0;
    const timeout = Duration(seconds: 10);
    while (true) {
      final request = await client.getUrl(destination);
      request.followRedirects = false;
      response = await request.close().timeout(timeout);
      if (!response.isRedirect) break;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || redirects++ == 4) {
        throw const HttpException('更新渠道的跳转地址不可用。');
      }
      destination = _httpsUrl(destination.resolve(location));
      await response.drain<void>().timeout(timeout);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('发布渠道暂时无法提供更新记录。');
    }
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    final records = jsonDecode(body);
    if (records is! List) throw const FormatException('更新记录应为列表。');
    final releases = <AppRelease>[];
    for (final record in records) {
      if (record is! Map<String, Object?>) {
        throw const FormatException('更新记录格式不正确。');
      }
      releases.add(AppRelease.fromJson(record));
    }
    return releases..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  } finally {
    client.close(force: true);
  }
}
