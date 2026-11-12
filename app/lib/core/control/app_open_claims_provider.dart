import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';

import 'app_open_claims.dart';

final appOpenClaimsProvider = Provider<AppOpenClaims>((ref) {
  ref.watch(videoSessionsProvider);
  final claims = AppOpenClaims();
  ref.onDispose(claims.close);
  return claims;
});
