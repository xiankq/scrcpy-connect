import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/app_release.dart';

void main() {
  final entry = Uri.parse('https://github.com/project/app/releases/latest');
  final asset = Uri.parse('https://release-assets.githubusercontent.com/feed');

  test('读取通过 HTTPS 跳转提供的发布清单', () async {
    final client = _FeedClient({
      entry: _FeedResponse.redirect(asset.toString()),
      asset: _FeedResponse.ok('''
[
  {
    "version": "0.2.0",
    "build": 2,
    "publishedAt": "2026-11-23T00:00:00Z",
    "notes": ["修复连接"],
    "url": "https://github.com/project/app/releases/tag/v0.2.0"
  }
]
'''),
    });

    final releases = await HttpOverrides.runZoned(
      () => readAppReleases(entry),
      createHttpClient: (_) => client,
    );

    expect(client.requests, [entry, asset]);
    expect(releases.single.version, '0.2.0');
    expect(releases.single.notes, ['修复连接']);
  });

  test('拒绝降级到 HTTP 的跳转', () async {
    final client = _FeedClient({
      entry: _FeedResponse.redirect('http://release-assets.example/feed'),
    });

    await expectLater(
      HttpOverrides.runZoned(
        () => readAppReleases(entry),
        createHttpClient: (_) => client,
      ),
      throwsFormatException,
    );
    expect(client.requests, [entry]);
  });
}

class _FeedClient extends Fake implements HttpClient {
  _FeedClient(this.responses);

  final Map<Uri, _FeedResponse> responses;
  final requests = <Uri>[];

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _FeedRequest(responses[url]!);
  }

  @override
  void close({bool force = false}) {}
}

class _FeedRequest extends Fake implements HttpClientRequest {
  _FeedRequest(this.response);
  final _FeedResponse response;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    return response;
  }
}

class _FeedResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FeedResponse.redirect(String location)
    : statusCode = HttpStatus.found,
      headers = _FeedHeaders(location),
      super(const Stream.empty());

  _FeedResponse.ok(String body)
    : statusCode = HttpStatus.ok,
      headers = _FeedHeaders(null),
      super(Stream.value(utf8.encode(body)));

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  @override
  bool get isRedirect => statusCode == HttpStatus.found;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FeedHeaders extends Fake implements HttpHeaders {
  _FeedHeaders(this.location);
  final String? location;

  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
}
