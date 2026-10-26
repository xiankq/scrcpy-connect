import '../control.dart';
import '../models.dart';
import '../api.dart';
import 'call.dart';
import '../event_observer.dart';
import 'generated/third_party/interop_scrcpy_api/api.dart' as native;

/// 独立 scrcpy 宿主的类型化适配；只解析配套 ADB 登记的连接。
final class FrbNativeScrcpyApi
    implements
        NativeScrcpyApi,
        NativeScrcpyConnectionApi,
        NativeScrcpyStagedApi,
        NativeScrcpySourceStatusApi,
        NativeScrcpyClipboardApi {
  const FrbNativeScrcpyApi();

  @override
  Future<String> readClipboard(String captureRef) =>
      nativeScrcpyCall(() => native.scrcpyGetClipboard(captureRef: captureRef));

  @override
  Future<ScrcpySourceStatus> sourceStatus({
    required String connectionId,
    required String captureRef,
    required String sourceId,
  }) async {
    final value = await nativeScrcpyCall(
      () => native.scrcpySourceStatus(
        connectionId: connectionId,
        captureRef: captureRef,
        sourceId: sourceId,
      ),
    );
    return ScrcpySourceStatus(
      captureRef: value.captureRef,
      sourceId: value.sourceId,
      generation: value.generation.toInt(),
      kind: ScrcpySourceKind.values.byName(value.kind.name),
      codec: value.codec,
      status: ScrcpySourceState.values.byName(value.status.name),
      packets: value.packets.toInt(),
      bytes: value.bytes.toInt(),
    );
  }

  @override
  Future<void> drainConnection(String connectionId) => nativeScrcpyCall(
    () => native.scrcpyDrainConnection(connectionId: connectionId),
  );

  @override
  Future<ScrcpySessionInfo> startControl(String sessionId) async => _info(
    await nativeScrcpyCall(
      () => native.scrcpyStartControl(sessionId: sessionId),
    ),
  );

  @override
  Future<ScrcpySessionInfo> awaitMedia(
    String captureRef, {
    int generation = 1,
  }) async => _info(
    await nativeScrcpyCall(
      () => native.scrcpyAwaitMedia(
        captureRef: captureRef,
        generation: BigInt.from(generation),
      ),
    ),
  );

  @override
  Future<ScrcpyProcessInfo> processInfo(String captureRef) async {
    final value = await nativeScrcpyCall(
      () => native.scrcpyProcessInfo(captureRef: captureRef),
    );
    return ScrcpyProcessInfo(
      pid: value.pid,
      started: value.started.toInt(),
      logTail: List.unmodifiable(value.logTail),
      truncated: value.truncated,
    );
  }

  ScrcpyNativeSource _source(native.ScrcpyNativeSource source) =>
      ScrcpyNativeSource(
        sourceId: source.sourceId,
        generation: source.generation.toInt(),
        codec: source.codec,
        width: source.width,
        height: source.height,
        attachAddress: source.attachAddress.toInt(),
        detachAddress: source.detachAddress.toInt(),
      );

  ScrcpySessionInfo _info(native.ScrcpySessionInfo value) => ScrcpySessionInfo(
    id: value.id,
    deviceName: value.deviceName,
    videoCodec: ScrcpyVideoCodec.values.byName(value.videoCodec.name),
    width: value.width,
    height: value.height,
    source: value.source == null ? null : _source(value.source!),
    audioSource: value.audioSource == null ? null : _source(value.audioSource!),
    videoEnabled: value.videoEnabled,
    audioEnabled: value.audioEnabled,
    controlReady: value.controlReady,
    mediaReady: value.mediaReady,
    processId: value.processId,
    processStarted: value.processStarted?.toInt(),
  );

  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) => nativeScrcpyCall(
    () => native.scrcpyCreateSession(
      connectionId: connectionId,
      options: native.ScrcpyOptions(
        logLevel: native.ScrcpyLogLevel.values.byName(options.logLevel.name),
        video: options.video,
        audio: options.audio,
        displayId: options.displayId,
        keepActive: options.keepActive,
        powerOffOnClose: options.powerOffOnClose,
        stayAwake: options.stayAwake,
        cleanup: options.cleanup,
        videoCodec: native.ScrcpyVideoCodec.values.byName(
          options.videoCodec.name,
        ),
        videoBitRate: options.videoBitRate,
        maxSize: options.maxSize,
        maxFps: options.maxFps,
        videoEncoder: options.videoEncoder,
        display: switch (options.display) {
          final display? => native.ScrcpyDisplayOptions(
            width: display.width,
            height: display.height,
            density: display.density,
          ),
          null => null,
        },
        control: options.control,
        powerOn: options.powerOn,
        clipboardAutosync: options.clipboardAutosync,
        vdDestroyContent: options.vdDestroyContent,
        flexDisplay: options.flexDisplay,
        vdSystemDecorations: options.vdSystemDecorations,
        repeatPreviousFrameAfterUs: options.repeatPreviousFrameAfterUs == null
            ? null
            : BigInt.from(options.repeatPreviousFrameAfterUs!),
      ),
    ),
  );

  @override
  Future<ScrcpySessionInfo> startSession(String sessionId) async => _info(
    await nativeScrcpyCall(
      () => native.scrcpyStartSession(sessionId: sessionId),
    ),
  );

  @override
  Future<ScrcpySessionInfo> inspect(
    String captureRef, {
    int generation = 1,
  }) async => _info(
    await nativeScrcpyCall(
      () => native.scrcpyInspect(
        captureRef: captureRef,
        generation: BigInt.from(generation),
      ),
    ),
  );

  @override
  Future<void> stopSession(String sessionId) =>
      nativeScrcpyCall(() => native.scrcpyStopSession(captureRef: sessionId));

  @override
  Future<ScrcpyControlReceipt> sendControl(
    String sessionId,
    ScrcpyControlMessage message,
  ) async {
    if (message is ScrcpyResizeDisplay &&
        (message.width < 1 ||
            message.width > 0xffff ||
            message.height < 1 ||
            message.height > 0xffff)) {
      // 在 FRB 的 u16 编码前拒绝越界，避免窄化后的尺寸被发送。
      throw const ScrcpyException('invalid_argument', '显示尺寸必须在 1 到 65535 之间。');
    }
    final receipt = await nativeScrcpyCall(
      () => switch (message) {
        ScrcpyKey() => native.scrcpyKey(
          captureRef: sessionId,
          action: native.ScrcpyKeyAction.values.byName(message.action.name),
          keycode: message.keycode,
          repeat: message.repeat,
          metaState: message.metaState,
        ),
        ScrcpyText() => native.scrcpyText(
          captureRef: sessionId,
          text: message.text,
        ),
        ScrcpyTouch() => native.scrcpyTouch(
          captureRef: sessionId,
          action: native.ScrcpyTouchAction.values.byName(message.action.name),
          pointerId: message.pointerId,
          x: message.x,
          y: message.y,
          width: message.width,
          height: message.height,
          pressure: message.pressure,
          actionButton: message.actionButton,
          buttons: message.buttons,
        ),
        ScrcpyScroll() => native.scrcpyScroll(
          captureRef: sessionId,
          x: message.x,
          y: message.y,
          width: message.width,
          height: message.height,
          horizontal: message.horizontal,
          vertical: message.vertical,
          buttons: message.buttons,
        ),
        ScrcpyClipboard() => native.scrcpyClipboard(
          captureRef: sessionId,
          text: message.text,
          paste: message.paste,
        ),
        ScrcpyRotate() => native.scrcpyRotate(captureRef: sessionId),
        ScrcpySetDisplayPower() => native.scrcpySetDisplayPower(
          captureRef: sessionId,
          on_: message.on,
        ),
        ScrcpyResizeDisplay() => native.scrcpyResizeDisplay(
          captureRef: sessionId,
          width: message.width,
          height: message.height,
        ),
        ScrcpyResetVideo() => native.scrcpyResetVideo(captureRef: sessionId),
        ScrcpyStartApp() => native.scrcpyStartApp(
          captureRef: sessionId,
          packageName: message.packageName,
        ),
      },
    );
    return ScrcpyControlReceipt(
      ScrcpyControlCompletion.values.byName(receipt.completion.name),
    );
  }

  @override
  ScrcpyEventObserver openEvents(String captureRef) => ScrcpyEventObserver(
    open: () => native.scrcpyOpenEvents(captureRef: captureRef),
    next: (id) async {
      final event = await nativeScrcpyCall(
        () => native.scrcpyNextEvent(observerId: id),
      );
      if (event == null) return null;
      if (event.captureRef != captureRef) {
        throw const ScrcpyException('stale_capture');
      }
      return switch (event.kind) {
        native.ScrcpyEventKind.clipboardChanged => ScrcpyClipboardChanged(
          event.text ?? '',
        ),
        native.ScrcpyEventKind.stopped => ScrcpyStopped(reason: event.reason),
      };
    },
    cancel: (id) =>
        nativeScrcpyCall(() => native.scrcpyCancelEvents(observerId: id)),
  );
}
