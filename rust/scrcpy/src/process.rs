//! 临时 app_process 部署的启动授权、精确任务监督与退出回执。
use crate::{
    Error, Result,
    process_identity::{ProcessLaunchState, launch_identity},
    shell_quote as quote,
};
use interop_adb::{AdbReader, AdbStream, AdbWriter, CancellationToken};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::Duration,
};

/// START 之前只读取输入，不启动任务或删除文件。PID 回执后等待 RUN，
/// STOP/EOF 在精确原任务 wait 完成后才发出本次唯一 DONE。
pub fn managed_launch_command(remote_jar: &str, command: &str) -> Result<String> {
    Ok(format!(
        r#"IFS= read -r start || exit 40
case "$start" in START:*) nonce=${{start#START:}} ;; *) exit 40 ;; esac
[ "${{#nonce}}" = 32 ] || exit 40
case "$nonce" in *[!0-9a-f]*) exit 40 ;; esac
run_owned() {{
IFS= read -r own_stat < /proc/self/stat || exit 40
own_pid=${{own_stat%% *}}
case "$own_pid" in ''|*[!0-9]*) exit 40 ;; esac
kill -STOP "$own_pid" || exit 40
{command};
}}
cleanup() {{
    result=$1
    trap - EXIT
    trap '' HUP INT TERM USR1 USR2
    for job in %1 %2; do
        jobs "$job" >/dev/null 2>&1
        kill -TERM "$job" 2>/dev/null
        kill -CONT "$job" 2>/dev/null
    done
    if [ -n "${{child:-}}" ]; then wait "$child" 2>/dev/null; fi
    if [ -n "${{watcher:-}}" ]; then wait "$watcher" 2>/dev/null; fi
    rm -f -- {path}
    print -r -- "
__INTEROP_DONE__$nonce"
    exit "$result"
}}
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP USR1
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
watch_input() {{
    while IFS= read -r action; do
        case "$action" in
            "STOP:$nonce") kill -USR1 $$; return ;;
        esac
    done
    kill -USR1 $$
}}
run_owned </dev/null &
child=$!
while :; do
    IFS= read -r stat < /proc/$child/stat || exit 40
    rest=${{stat##*) }}
    set -- $rest
    state=$1
    shift 19 || exit 40
    started=$1
    case "$started" in ''|*[!0-9]*) exit 40 ;; esac
    case "$state" in T) break ;; Z|X|x) exit 40 ;; esac
done
print -r -- "__INTEROP_PID__$child:$started"
# RUN 前由父 shell 阻塞读取；不在等待网络授权时忙等。
while IFS= read -r action; do
    case "$action" in
        "RUN:$nonce") break ;;
        "STOP:$nonce") cleanup 129 ;;
    esac
done
[ "$action" = "RUN:$nonce" ] || cleanup 129
exec 3<&0
watch_input <&3 &
watcher=$!
exec 3<&-
jobs %1 >/dev/null 2>&1
kill -CONT %1 2>/dev/null || exit 40
wait "$child"
exit "$?""#,
        path = quote(remote_jar)?
    ))
}

#[derive(Default)]
struct Output {
    bytes: VecDeque<u8>,
    finished: bool,
    error: Option<String>,
}

/// 原生监督任务拥有实际 ADB 流；日志句柄释放只请求 STOP，不丢弃退出回执。
pub struct ManagedProcess {
    output: Arc<Mutex<Output>>,
    changed: Arc<tokio::sync::Notify>,
    stop: CancellationToken,
}

impl ManagedProcess {
    pub(crate) fn start(
        stream: AdbStream,
        state: ProcessLaunchState,
        cancellation: &CancellationToken,
    ) -> Self {
        let output = Arc::new(Mutex::new(Output::default()));
        let changed = Arc::new(tokio::sync::Notify::new());
        let stop = cancellation.child_token();
        state.activate();
        tokio::spawn({
            let output = output.clone();
            let changed = changed.clone();
            let stop = stop.clone();
            async move {
                let nonce = uuid::Uuid::new_v4().simple().to_string();
                let (reader, writer) = stream.into_split();
                let read_finished = CancellationToken::new();
                let (read, write) = tokio::join!(
                    read_output(
                        reader,
                        &nonce,
                        &state,
                        &output,
                        &changed,
                        &stop,
                        &read_finished
                    ),
                    write_commands(writer, &nonce, &state, &stop, &read_finished),
                );
                // 两个 future 均拥有并已释放原半流，完成信号不早于本机 FD/路由释放。
                let error = if state.done() {
                    None
                } else {
                    read.err()
                        .or_else(|| write.err())
                        .map(|error| error.to_string())
                };
                {
                    let mut output = output.lock().expect("进程日志");
                    output.finished = true;
                    output.error = error.clone();
                }
                state.finish(error);
                changed.notify_waiters();
            }
        });
        Self {
            output,
            changed,
            stop,
        }
    }

    pub async fn read(&mut self, bytes: &mut [u8]) -> Result<usize> {
        if bytes.is_empty() {
            return Ok(0);
        }
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let mut output = self.output.lock().expect("进程日志");
                let count = bytes.len().min(output.bytes.len());
                for byte in &mut bytes[..count] {
                    *byte = output.bytes.pop_front().expect("日志长度已核对");
                }
                if count != 0 {
                    return Ok(count);
                }
                if output.finished {
                    return match &output.error {
                        Some(error) => Err(Error::new("process_cleanup_unverified", error.clone())),
                        None => Ok(0),
                    };
                }
            }
            changed.await;
        }
    }
}

impl Drop for ManagedProcess {
    fn drop(&mut self) {
        self.stop.cancel();
    }
}

async fn write_command(writer: &mut AdbWriter, action: &str, nonce: &str) -> Result<()> {
    tokio::time::timeout(
        Duration::from_secs(3),
        writer.write_all(format!("{action}:{nonce}\n").as_bytes()),
    )
    .await
    .map_err(|_| Error::new("process_cleanup_unverified", "监督命令未在期限内写入。"))??;
    Ok(())
}

async fn write_commands(
    mut writer: AdbWriter,
    nonce: &str,
    state: &ProcessLaunchState,
    stop: &CancellationToken,
    read_finished: &CancellationToken,
) -> Result<()> {
    if stop.is_cancelled() {
        return Ok(());
    }
    state.start_attempted();
    let result = async {
        write_command(&mut writer, "START", nonce).await?;
        let run = tokio::select! {
            biased;
            _=stop.cancelled()=>false,
            _=read_finished.cancelled()=>return Ok(()),
            identity=state.identity()=>identity.is_ok(),
        };
        if run && !stop.is_cancelled() {
            write_command(&mut writer, "RUN", nonce).await?;
            state.running_received();
            tokio::select! {
                _=stop.cancelled()=>{},
                _=read_finished.cancelled()=>return Ok(()),
            }
        }
        stop.cancel();
        write_command(&mut writer, "STOP", nonce).await?;
        read_finished.cancelled().await;
        Ok(())
    }
    .await;
    if result.is_err() {
        stop.cancel();
    }
    result
}

fn append_output(output: &Mutex<Output>, changed: &tokio::sync::Notify, bytes: &[u8]) {
    // 无日志消费者时也不能阻塞监督终态；只保留有界事实尾部。
    const MAX_LOG: usize = 64 * 1024;
    let mut output = output.lock().expect("进程日志");
    for byte in bytes {
        if output.bytes.len() == MAX_LOG {
            output.bytes.pop_front();
        }
        output.bytes.push_back(*byte);
    }
    changed.notify_waiters();
}

async fn read_output(
    mut reader: AdbReader,
    nonce: &str,
    state: &ProcessLaunchState,
    output: &Mutex<Output>,
    changed: &tokio::sync::Notify,
    stop: &CancellationToken,
    read_finished: &CancellationToken,
) -> Result<()> {
    let _finished = read_finished.clone().drop_guard();
    let done = format!("__INTEROP_DONE__{nonce}");
    let mut line = Vec::new();
    let mut log_line = false;
    let mut identity_received = false;
    let mut stopping = false;
    let mut deadline = tokio::time::Instant::now();
    loop {
        let mut bytes = [0; 4096];
        let count = tokio::select! {
            biased;
            _=stop.cancelled(), if !stopping=>{
                stopping=true;
                deadline=tokio::time::Instant::now()+Duration::from_secs(3);
                continue;
            },
            _=tokio::time::sleep_until(deadline), if stopping=>return Err(Error::new("process_cleanup_unverified", "监督器未在停止期限内确认原任务退出。")),
            result=reader.read(&mut bytes)=>result?,
        };
        if count == 0 {
            append_output(output, changed, &line);
            return Err(Error::new(
                "process_cleanup_unverified",
                "监督流已结束，但未收到本次退出回执。",
            ));
        }
        for byte in &bytes[..count] {
            line.push(*byte);
            if *byte == b'\n' {
                let content = line.strip_suffix(b"\n").expect("已读到换行");
                let content = content.strip_suffix(b"\r").unwrap_or(content);
                if !log_line && content == done.as_bytes() {
                    state.done_received();
                    return Ok(());
                }
                if !log_line && !identity_received && content.starts_with(b"__INTEROP_PID__") {
                    state.identity_received(launch_identity(content)?);
                    identity_received = true;
                } else {
                    append_output(output, changed, &line);
                }
                line.clear();
                log_line = false;
            } else if line.len() >= 8192 {
                append_output(output, changed, &line);
                line.clear();
                log_line = true;
            }
        }
    }
}
