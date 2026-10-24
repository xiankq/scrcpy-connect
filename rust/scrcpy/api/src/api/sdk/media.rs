//! 捕获的媒体任务只解释协议与原生来源，不持有窗口、焦点或产品播放策略。
use super::*;

pub(super) async fn prepare_video(
    capture: Arc<Capture>,
    mut video: interop_adb::AdbStream,
    initial: [u8; 12],
) {
    let _finished = capture.video_finished.clone().drop_guard();
    let result = async {
        capture.media_requested.cancelled().await;
        let (preface, width, height) =
            interop_scrcpy::capture::read_video_preface(&mut video, initial)
                .await
                .map_err(|error| error.to_string())?;
        let source = register_source(
            &capture,
            interop_scrcpy::media::native::video_codec_id(capture.options.codec.name())
                .map_err(|error| error.to_string())?,
            width,
            height,
        )?;
        {
            let mut phase = capture.phase.lock().expect("SDK 捕获状态");
            if *phase != Phase::ControlReady || capture.cancellation.is_cancelled() {
                return Err("cancelled: 捕获已停止。".to_owned());
            }
            *capture.source.lock().expect("SDK 来源") = Some(source.clone());
            let mut info = capture.info.lock().expect("SDK 元数据");
            let info = info.as_mut().expect("控制接纳先于媒体任务");
            info.width = width;
            info.height = height;
            info.media_ready = true;
            *phase = Phase::Running;
        }
        capture.media_ready.cancel();
        interop_scrcpy::media::video::forward_video(
            source,
            video,
            preface,
            capture.cancellation.clone(),
        )
        .await
        .map_err(|error| error.to_string())
    };
    let result = tokio::select! {
        _ = capture.cancellation.cancelled() => Ok(()),
        result = result => result,
    };
    if let Err(error) = result {
        *capture.media_error.lock().expect("SDK 媒体启动结果") = Some(error);
    }
    capture.media_ready.cancel();
    capture.cancellation.cancel();
}

pub(super) async fn forward_audio(
    capture: Arc<Capture>,
    source: Arc<MediaSource>,
    audio: interop_adb::AdbStream,
) {
    let _finished = capture.audio_finished.clone().drop_guard();
    let mut audio = audio;
    let operation = async {
        source
            .wait_attached()
            .await
            .map_err(|error| error.to_string())?;
        source
            .configure(0, 0, &[])
            .await
            .map_err(|error| error.to_string())?;
        loop {
            let packet = interop_scrcpy::audio::read_pcm_packet(&mut audio)
                .await
                .map_err(|error| error.to_string())?;
            if packet.bytes.is_empty() {
                continue;
            }
            source
                .packet_owned(packet.bytes, packet.pts_us, true)
                .await
                .map_err(|error| error.to_string())?;
        }
        #[allow(unreachable_code)]
        Ok::<_, String>(())
    };
    let result = tokio::select! {
        _ = capture.cancellation.cancelled() => Ok(()),
        result = operation => result,
    };
    if let Err(error) = result {
        *capture.media_error.lock().expect("SDK 媒体启动结果") = Some(error);
    }
    source.finish();
    // 先释放本机 PCM 流，再由完成票据允许 cleanup flush/rm。
    drop(audio);
    capture.cancellation.cancel();
}
