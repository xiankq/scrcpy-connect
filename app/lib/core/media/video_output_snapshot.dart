/// 合并核心会话状态与最新渲染输出。
/// 播放器回执可能携带恢复请求时的旧核心状态，因此只有渲染证据可覆盖当前会话快照。
Map<String, dynamic> sessionWithVideoOutput(
  Map<String, dynamic> session,
  Map<String, dynamic>? output,
) {
  final capture = session['captureGeneration'];
  final outputCapture = output?['captureGeneration'];
  final renderer = session['rendererGeneration'];
  final outputRenderer = output?['generation'];
  final previousCapture =
      capture is int && output != null && capture != outputCapture;
  final previousRenderer =
      renderer is int && outputRenderer is int && outputRenderer < renderer;
  if (previousCapture || previousRenderer) {
    return {
      ...session,
      for (final key in const [
        'textureId',
        'decodedWidth',
        'decodedHeight',
        'backend',
      ])
        if (output?.containsKey(key) == true) key: output![key],
      'outputCaptureGeneration': outputCapture,
      'outputGeneration': outputRenderer,
      'outputRetained': true,
      'firstFrameDecoded': false,
      'evidence': 'retained_previous_output',
    };
  }
  return {
    ...session,
    for (final key in const [
      'relayId',
      'textureId',
      'decodedWidth',
      'decodedHeight',
      'decoderName',
      'hardwareAccelerated',
      'generation',
      'backend',
      'firstFrameDecoded',
      'evidence',
      'snapshotReceipts',
      'decodedReceipts',
      'platformTexturePrepared',
      'presentedSequence',
      'presentationPath',
      'presentedToWidget',
      'continuousFrameTelemetry',
      'outputStartupTimingMs',
    ])
      if (output?.containsKey(key) == true) key: output![key],
    if (outputCapture is int) 'outputCaptureGeneration': outputCapture,
    if (outputCapture is int && outputRenderer is int)
      'outputGeneration': outputRenderer,
  };
}
