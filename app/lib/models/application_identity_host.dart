final class ApplicationIdentityHost {
  const ApplicationIdentityHost({
    required this.identityPath,
    required this.fingerprint,
    required this.directory,
    this.serverId,
  });
  final String identityPath, fingerprint, directory;
  final String? serverId;

  factory ApplicationIdentityHost.fromJson(Map<String, Object?> value) {
    for (final key in ['identityPath', 'fingerprint', 'directory']) {
      if (value[key] is! String || (value[key] as String).isEmpty) {
        throw const FormatException('宿主身份事实缺失。');
      }
    }
    if (value['serverId'] != null && value['serverId'] is! String) {
      throw const FormatException('宿主服务器身份无效。');
    }
    return ApplicationIdentityHost(
      identityPath: value['identityPath'] as String,
      fingerprint: value['fingerprint'] as String,
      directory: value['directory'] as String,
      serverId: value['serverId'] as String?,
    );
  }

  ApplicationIdentityHost withServer(String id) => ApplicationIdentityHost(
    identityPath: identityPath,
    fingerprint: fingerprint,
    directory: directory,
    serverId: id,
  );

  Map<String, Object?> toJson() => {
    'identityPath': identityPath,
    'fingerprint': fingerprint,
    'directory': directory,
    'serverId': serverId,
  };
}
