import 'package:freezed_annotation/freezed_annotation.dart';

part 'authorization_identity.freezed.dart';

enum IdentityScope { global, device }

/// 可呈现的授权身份；不含私钥或 SDK 使用的本机材料路径。
@freezed
class AuthorizationIdentity with _$AuthorizationIdentity {
  AuthorizationIdentity({
    required this.scope,
    required this.fingerprint,
    this.deviceId,
    List<String> affectedDeviceIds = const [],
  }) : affectedDeviceIds = List.unmodifiable(affectedDeviceIds);

  final IdentityScope scope;
  final String fingerprint;
  final String? deviceId;
  final List<String> affectedDeviceIds;
}
