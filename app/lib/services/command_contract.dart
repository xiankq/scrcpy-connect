import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/application_command.dart';

/// 内部路由入口的防御性检查；权限、身份和资源代际仍由业务所有者核验。
ApplicationCommand validateCommandRequest(
  String name,
  Map<String, dynamic> params,
) {
  final command = ApplicationCommand.tryParse(name);
  if (command == null) {
    throw ApplicationCommandException('unknown_command', '未知操作：$name');
  }
  validateTypedCommandRequest(command, params);
  return command;
}

void validateTypedCommandRequest(
  ApplicationCommand command,
  Map<String, dynamic> params,
) {
  switch (command) {
    case ApplicationCommand.activitiesStop:
      _check(params, 'activityId', _string, 'invalid_argument');
    case ApplicationCommand.appsForeground ||
        ApplicationCommand.deviceDataGet ||
        ApplicationCommand.deviceNetworkGet ||
        ApplicationCommand.deviceScreenState ||
        ApplicationCommand.devicesWake:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(
        params,
        'connectionId',
        _string,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.appsIcon:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'packageName', _string, 'invalid_argument');
    case ApplicationCommand.appsLaunch ||
        ApplicationCommand.audioStart ||
        ApplicationCommand.callsAction ||
        ApplicationCommand.callsList ||
        ApplicationCommand.callsOpen ||
        ApplicationCommand.callsOpenPhoneApp ||
        ApplicationCommand.clipboardGet ||
        ApplicationCommand.clipboardSet ||
        ApplicationCommand.deviceCapabilities ||
        ApplicationCommand.deviceDiagnose ||
        ApplicationCommand.deviceInfo ||
        ApplicationCommand.devicesDisconnect ||
        ApplicationCommand.devicesForget ||
        ApplicationCommand.devicesRename ||
        ApplicationCommand.filesList ||
        ApplicationCommand.filesMkdir ||
        ApplicationCommand.identityDeviceGet ||
        ApplicationCommand.identityDeviceUseGlobal ||
        ApplicationCommand.mediaList ||
        ApplicationCommand.mediaPreview ||
        ApplicationCommand.mediaThumbnail ||
        ApplicationCommand.notificationsDismiss ||
        ApplicationCommand.notificationsList ||
        ApplicationCommand.notificationsOpen ||
        ApplicationCommand.observationStart ||
        ApplicationCommand.observationStatus ||
        ApplicationCommand.observationStop:
      _check(params, 'deviceId', _string, 'invalid_argument');
    case ApplicationCommand.appsList:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'filter', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.audioVolume:
      _check(params, 'volume', _number, 'invalid_argument', optional: true);
      _check(params, 'muted', _boolean, 'invalid_argument', optional: true);
    case ApplicationCommand.devicesAdd ||
        ApplicationCommand.devicesPair ||
        ApplicationCommand.devicesUsb:
      _check(params, 'identity', _object, 'invalid_argument', optional: true);
    case ApplicationCommand.devicesConfigure:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'address', _string, 'invalid_argument');
      _check(params, 'port', _integer, 'invalid_argument');
      _check(params, 'transport', _string, 'invalid_argument');
      _check(params, 'attemptId', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.devicesConnect:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'automatic', _boolean, 'invalid_argument', optional: true);
      _check(params, 'ownerId', _string, 'invalid_argument', optional: true);
      _check(params, 'attemptId', _string, 'invalid_argument', optional: true);
      _check(
        params,
        'candidateSource',
        _string,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'parentOperationId',
        _string,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.devicesPairQr:
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
      _check(params, 'identity', _object, 'invalid_argument', optional: true);
    case ApplicationCommand.devicesReconnectOwner:
      _check(params, 'ownerId', _string, 'invalid_argument');
      _check(params, 'active', _boolean, 'invalid_argument');
    case ApplicationCommand.devicesWireless:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'address', _string, 'invalid_argument');
      _check(params, 'port', _integer, 'invalid_argument', optional: true);
      _check(params, 'attemptId', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.filesDelete:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'expectedStamps', _object, 'invalid_argument');
    case ApplicationCommand.filesOpen || ApplicationCommand.mediaCacheRetain:
      _check(params, 'localPath', _string, 'invalid_argument');
    case ApplicationCommand.filesRename:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'expectedStamp', _object, 'invalid_argument');
    case ApplicationCommand.filesSearchCancel ||
        ApplicationCommand.filesSearchGet:
      _check(params, 'searchId', _string, 'invalid_argument');
      _check(params, 'deviceId', _string, 'invalid_argument');
    case ApplicationCommand.filesSearchStart:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'path', _string, 'invalid_argument');
      _check(params, 'query', _text, 'invalid_argument');
      _check(params, 'filter', _string, 'invalid_argument');
    case ApplicationCommand.identityDeviceImport:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'privateKeyPem', _string, 'invalid_argument');
    case ApplicationCommand.identityGlobalImport:
      _check(params, 'privateKeyPem', _string, 'invalid_argument');
    case ApplicationCommand.mediaCacheAcquire ||
        ApplicationCommand.transfersGet ||
        ApplicationCommand.transfersResolve ||
        ApplicationCommand.transfersResume:
      _check(params, 'transferId', _string, 'invalid_argument');
    case ApplicationCommand.mediaCacheConfigure:
      _check(
        params,
        'outgoingDirectory',
        _string,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'budgetBytes',
        _integer,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.mediaCacheRelease ||
        ApplicationCommand.sharingRelease:
      _check(params, 'leaseId', _string, 'invalid_argument');
    case ApplicationCommand.mediaOpen:
      _check(params, 'sourceId', _string, 'invalid_argument');
      _check(params, 'kind', _string, 'invalid_argument');
    case ApplicationCommand.mediaStatus:
      _check(params, 'relayId', _string, 'invalid_argument');
    case ApplicationCommand.sessionDisplay:
      _check(params, 'sessionId', _string, 'invalid_argument');
      _check(params, 'displayWidth', _integer, 'invalid_argument');
      _check(params, 'displayHeight', _integer, 'invalid_argument');
    case ApplicationCommand.sessionFrame:
      _check(params, 'sessionId', _string, 'invalid_argument');
      _check(params, 'generation', _integer, 'invalid_argument');
      _check(params, 'captureGeneration', _integer, 'invalid_argument');
      _check(params, 'textureId', _integer, 'invalid_argument');
      _check(params, 'decodedWidth', _integer, 'invalid_argument');
      _check(params, 'decodedHeight', _integer, 'invalid_argument');
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.sessionKey:
      _check(params, 'captureGeneration', _integer, 'invalid_argument');
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
      _check(params, 'action', _string, 'invalid_argument', optional: true);
      _check(params, 'keyCode', _integer, 'invalid_argument', optional: true);
      _check(params, 'metaState', _integer, 'invalid_argument', optional: true);
      _check(params, 'repeat', _integer, 'invalid_argument', optional: true);
    case ApplicationCommand.sessionLaunch ||
        ApplicationCommand.sessionList ||
        ApplicationCommand.sessionPause ||
        ApplicationCommand.sessionQuality ||
        ApplicationCommand.sessionQualityOptions ||
        ApplicationCommand.sessionRefresh ||
        ApplicationCommand.sessionResume ||
        ApplicationCommand.sessionRotate ||
        ApplicationCommand.sessionScreen ||
        ApplicationCommand.sessionScreenshot ||
        ApplicationCommand.sessionStop:
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.sessionReady:
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
      _check(
        params,
        'captureGeneration',
        _integer,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.sessionReconfigure:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(params, 'sessionId', _string, 'invalid_argument');
      _check(params, 'maxSize', _integer, 'invalid_argument', optional: true);
      _check(params, 'maxFps', _integer, 'invalid_argument', optional: true);
      _check(
        params,
        'videoBitRate',
        _integer,
        'invalid_argument',
        optional: true,
      );
      _check(params, 'videoCodec', _string, 'invalid_argument', optional: true);
      _check(
        params,
        'videoEncoder',
        _string,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'qualityPreset',
        _string,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.sessionScroll:
      _check(params, 'captureGeneration', _integer, 'invalid_argument');
      _check(params, 'x', _integer, 'invalid_argument');
      _check(params, 'y', _integer, 'invalid_argument');
      _check(params, 'screenWidth', _integer, 'invalid_argument');
      _check(params, 'screenHeight', _integer, 'invalid_argument');
      _check(params, 'hscroll', _number, 'invalid_argument');
      _check(params, 'vscroll', _number, 'invalid_argument');
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
      _check(params, 'buttons', _integer, 'invalid_argument', optional: true);
    case ApplicationCommand.sessionStart:
      _check(params, 'deviceId', _string, 'invalid_argument');
      _check(
        params,
        'displayWidth',
        _integer,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'displayHeight',
        _integer,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'displayAuto',
        _boolean,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'keepActive',
        _boolean,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'packageName',
        _string,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.sessionText:
      _check(params, 'captureGeneration', _integer, 'invalid_argument');
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
    case ApplicationCommand.sessionTouch:
      _check(params, 'captureGeneration', _integer, 'invalid_argument');
      _check(params, 'sessionId', _string, 'invalid_argument', optional: true);
      _check(params, 'deviceId', _string, 'invalid_argument', optional: true);
      _check(params, 'action', _string, 'invalid_argument', optional: true);
      _check(params, 'pressure', _number, 'invalid_argument', optional: true);
      _check(params, 'mouse', _boolean, 'invalid_argument', optional: true);
      _check(params, 'buttons', _integer, 'invalid_argument', optional: true);
      _check(
        params,
        'actionButton',
        _integer,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.settingsImport:
      _check(params, 'metadata', _object, 'invalid_argument');
      _check(params, 'fingerprint', _string, 'invalid_argument');
      _check(
        params,
        'importGlobalPreferences',
        _boolean,
        'invalid_argument',
        optional: true,
      );
      _check(
        params,
        'expectedRevision',
        _integer,
        'invalid_argument',
        optional: true,
      );
    case ApplicationCommand.settingsImportPreview:
      _check(params, 'metadata', _object, 'invalid_argument');
    case ApplicationCommand.sharingBind:
      _check(params, 'leaseId', _string, 'invalid_argument');
      _check(params, 'transferId', _string, 'invalid_argument');
    case ApplicationCommand.sharingCancel ||
        ApplicationCommand.sharingConsume ||
        ApplicationCommand.sharingImport ||
        ApplicationCommand.sharingRetain:
      _check(params, 'shareId', _string, 'invalid_argument');
    case ApplicationCommand.sharingConfigure:
      _check(params, 'absoluteRoot', _string, 'invalid_argument');
      _check(params, 'allowedCacheRoot', _string, 'invalid_argument');
    case ApplicationCommand.transfersCancel ||
        ApplicationCommand.transfersRemove:
      _check(params, 'transferId', _string, 'invalid_argument', optional: true);
      _check(params, 'batchId', _string, 'invalid_argument', optional: true);
    default:
      break;
  }
}

void validateCommandResult(
  ApplicationCommand command,
  Map<String, dynamic> result,
) {
  switch (command) {
    case ApplicationCommand.activitiesList:
      _check(result, 'activities', _array, 'invalid_response');
    case ApplicationCommand.appsIcon:
      _check(result, 'deviceId', _string, 'invalid_response');
      _check(result, 'packageName', _string, 'invalid_response');
      _check(result, 'mimeType', _string, 'invalid_response');
      _check(result, 'dataBase64', _string, 'invalid_response');
      _check(result, 'width', _integer, 'invalid_response');
      _check(result, 'height', _integer, 'invalid_response');
    case ApplicationCommand.audioSources:
      _check(result, 'sources', _array, 'invalid_response');
    case ApplicationCommand.devicesList:
      _check(result, 'devices', _array, 'invalid_response');
    case ApplicationCommand.identityDeviceGet ||
        ApplicationCommand.identityDeviceImport ||
        ApplicationCommand.identityDeviceUseGlobal ||
        ApplicationCommand.identityGlobalGet ||
        ApplicationCommand.identityGlobalImport ||
        ApplicationCommand.identityGlobalReset:
      _check(result, 'scope', _string, 'invalid_response');
      _check(result, 'fingerprint', _string, 'invalid_response');
    case ApplicationCommand.sessionList:
      _check(result, 'sessions', _array, 'invalid_response');
    case ApplicationCommand.settingsExport:
      _check(result, 'metadata', _object, 'invalid_response');
    case ApplicationCommand.settingsImportPreview:
      _check(result, 'fingerprint', _string, 'invalid_response');
      _check(result, 'newRecords', _integer, 'invalid_response');
      _check(result, 'alreadyImported', _boolean, 'invalid_response');
      _check(result, 'expectedRevision', _integer, 'invalid_response');
      _check(result, 'globalChanges', _array, 'invalid_response');
    case ApplicationCommand.sharingPending:
      _check(result, 'shares', _array, 'invalid_response');
    case ApplicationCommand.stateSnapshot:
      _check(result, 'sequence', _integer, 'invalid_response');
      _check(result, 'settings', _object, 'invalid_response');
      _check(result, 'devices', _array, 'invalid_response');
      _check(result, 'sessions', _array, 'invalid_response');
      _check(result, 'sources', _array, 'invalid_response');
      _check(result, 'transfers', _array, 'invalid_response');
      _check(result, 'activities', _array, 'invalid_response');
      _check(result, 'shares', _array, 'invalid_response');
      _check(result, 'companions', _array, 'invalid_response');
      _check(result, 'observations', _array, 'invalid_response');
    case ApplicationCommand.systemInfo:
      _check(result, 'appName', _text, 'invalid_response');
      _check(result, 'packageName', _text, 'invalid_response');
      _check(result, 'version', _string, 'invalid_response');
      _check(result, 'buildNumber', _text, 'invalid_response');
    case ApplicationCommand.transfersList:
      _check(result, 'transfers', _array, 'invalid_response');
    default:
      break;
  }
}

void _check(
  Map<String, dynamic> data,
  String key,
  bool Function(Object?) accepts,
  String code, {
  bool optional = false,
}) {
  final value = data[key];
  if (optional && value == null) return;
  if (!accepts(value)) {
    throw ApplicationCommandException(
      code,
      optional ? '无效的字段：$key' : '缺少或无效的字段：$key',
    );
  }
}

bool _string(Object? value) =>
    value is String && value.isNotEmpty && !value.contains('\u0000');
bool _text(Object? value) => value is String && !value.contains('\u0000');
bool _integer(Object? value) => value is int;
bool _number(Object? value) => value is num && value.isFinite;
bool _boolean(Object? value) => value is bool;
bool _object(Object? value) => value is Map<String, dynamic>;
bool _array(Object? value) => value is List;
