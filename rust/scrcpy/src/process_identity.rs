//! 精确进程身份核验与有界退出证明。
use crate::{Error, Result, shell_quote};
use interop_adb::OperationOptions;
use std::{
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::Notify;

#[derive(Default)]
struct LaunchFacts {
    active: bool,
    started: bool,
    identity: Option<(u32, u64)>,
    running: bool,
    done: bool,
    finished: bool,
    error: Option<String>,
}

/// 在启动前保存的精确责任；启动失败不能因未交付进程句柄而丢失退出核验。
#[derive(Clone, Default)]
pub struct ProcessLaunchState {
    facts: Arc<Mutex<LaunchFacts>>,
    changed: Arc<Notify>,
}

impl ProcessLaunchState {
    pub(crate) fn activate(&self) {
        self.facts.lock().expect("进程启动状态").active = true;
    }
    pub(crate) fn start_attempted(&self) {
        // 写入失败也可能已交付部分或全部 START，不能回退成无副作用状态。
        self.facts.lock().expect("进程启动状态").started = true;
    }
    pub(crate) fn identity_received(&self, identity: (u32, u64)) {
        self.facts.lock().expect("进程启动状态").identity = Some(identity);
        self.changed.notify_waiters();
    }
    pub(crate) fn done_received(&self) {
        self.facts.lock().expect("进程启动状态").done = true;
    }
    pub(crate) fn running_received(&self) {
        self.facts.lock().expect("进程启动状态").running = true;
        self.changed.notify_waiters();
    }
    pub(crate) async fn running(&self) -> Result<(u32, u64)> {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let facts = self.facts.lock().expect("进程启动状态");
                if facts.running {
                    return facts
                        .identity
                        .ok_or_else(|| Error::new("process_identity", "运行授权缺少进程身份。"));
                }
                if facts.finished {
                    return Err(Error::new(
                        "process_launch",
                        facts
                            .error
                            .clone()
                            .unwrap_or_else(|| "进程未取得运行授权。".into()),
                    ));
                }
            }
            changed.await;
        }
    }
    pub(crate) fn done(&self) -> bool {
        self.facts.lock().expect("进程启动状态").done
    }
    pub(crate) fn finish(&self, error: Option<String>) {
        let mut facts = self.facts.lock().expect("进程启动状态");
        facts.finished = true;
        facts.error = error;
        self.changed.notify_waiters();
    }
    pub(crate) async fn identity(&self) -> Result<(u32, u64)> {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let facts = self.facts.lock().expect("进程启动状态");
                if let Some(identity) = facts.identity {
                    return Ok(identity);
                }
                if facts.finished {
                    return Err(Error::new(
                        "process_identity",
                        facts
                            .error
                            .clone()
                            .unwrap_or_else(|| "进程未报告身份。".into()),
                    ));
                }
            }
            changed.await;
        }
    }

    /// 调用方先等启动操作结束；本方法也等监督器释放全部本机流。
    /// 唯一 DONE 或精确内核身份退出才是远端证明，断流和缺少身份都不是。
    pub async fn wait_exited(&self, client: &interop_adb::Client) -> Result<()> {
        tokio::time::timeout(Duration::from_secs(7), async {
            loop {
                let changed = self.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                {
                    let facts = self.facts.lock().expect("进程启动状态");
                    if !facts.active || facts.finished {
                        break;
                    }
                }
                changed.await;
            }
        })
        .await
        .map_err(|_| Error::new("process_cleanup_unverified", "进程监督流尚未确认释放。"))?;
        let (started, done, identity) = {
            let facts = self.facts.lock().expect("进程启动状态");
            (facts.started, facts.done, facts.identity)
        };
        if !started || done {
            return Ok(());
        }
        let Some((pid, started)) = identity else {
            return Err(Error::new(
                "process_cleanup_unverified",
                "启动授权可能已交付，但未取得身份或退出回执。",
            ));
        };
        RemoteProcessIdentity {
            pid,
            started,
            identity: String::new(),
        }
        .wait_exited(client)
        .await
    }
}

#[derive(Clone)]
pub struct RemoteProcessIdentity {
    pub pid: u32,
    pub started: u64,
    pub identity: String,
}

pub fn launch_identity(bytes: &[u8]) -> Result<(u32, u64)> {
    let parsed = std::str::from_utf8(bytes)
        .ok()
        .and_then(|line| line.strip_prefix("__INTEROP_PID__"))
        .and_then(|fields| fields.split_once(':'))
        .filter(|(pid, started)| {
            !pid.is_empty()
                && !started.is_empty()
                && pid.bytes().all(|byte| byte.is_ascii_digit())
                && started.bytes().all(|byte| byte.is_ascii_digit())
        })
        .and_then(|(pid, started)| Some((pid.parse::<u32>().ok()?, started.parse::<u64>().ok()?)))
        .filter(|(pid, started)| *pid > 1 && *started > 0);
    parsed.ok_or_else(|| Error::new("process_identity", "服务进程启动标识缺失或无效。"))
}

impl RemoteProcessIdentity {
    pub async fn capture(
        client: &interop_adb::Client,
        pid: u32,
        started: u64,
        identity: String,
    ) -> Result<Self> {
        // 启动器 shell 交接前读取子进程启动时间，exec 保留它；下方核验相同内核身份与完整 JAR/SCID nice-name，不再发第二次 stat。
        let process = Self {
            pid,
            started,
            identity,
        };
        // verify 构造较大内联 shell 程序；装箱使默认测试线程栈上的进程启动状态机保持较小。
        Box::pin(process.verify(client)).await?;
        Ok(process)
    }

    /// 本地 exec 路由关闭仅请求监督器清理；释放进程回执前须确认精确内核身份已退出。
    pub fn exit_wait_command(&self) -> String {
        format!(
            r#"p={pid}
expected={started}
while :; do
  if [ ! -e /proc/$p ]; then print -r -- released:absent; exit 0; fi
  IFS= read -r stat < /proc/$p/stat || exit 42
  rest=${{stat##*) }}
  set -- $rest
  state=$1
  shift 19 || exit 42
  case "$1" in ''|*[!0-9]*) exit 42 ;; esac
  if [ "$1" != "$expected" ]; then print -r -- released:replaced; exit 0; fi
  case "$state" in Z|X|x) print -r -- released:exited; exit 0 ;; esac
  sleep 0.02 || exit 42
done"#,
            pid = self.pid,
            started = self.started
        )
    }

    pub async fn wait_exited(&self, client: &interop_adb::Client) -> Result<()> {
        let result = client
            .shell(
                &self.exit_wait_command(),
                4096,
                OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                },
            )
            .await?;
        if result.exit_code.is_some_and(|code| code != 0)
            || !matches!(
                result.stdout.as_slice(),
                b"released:absent\n"
                    | b"released:replaced\n"
                    | b"released:exited\n"
                    | b"released:absent\r\n"
                    | b"released:replaced\r\n"
                    | b"released:exited\r\n"
            )
        {
            return Err(Error::new(
                "process_cleanup_unverified",
                "无法确认原窗口服务进程已经退出。",
            ));
        }
        Ok(())
    }

    pub async fn verify(&self, client: &interop_adb::Client) -> Result<()> {
        // 在 shell 内重新核验，包括内核启动时间，不跨独立 shell 调用保留数字 PID。app_process 改写 argv[0]；显式设置含私有 JAR 路径及 SCID 的唯一 nice-name，并匹配完整参数。
        let identity = shell_quote(&self.identity)?;
        let command = format!(
            r#"p={pid}
expected={started}
identity() {{
  IFS= read -r stat < /proc/$p/stat || return 1
  rest=${{stat##*) }}
  set -- $rest
  state=$1
  shift 19 || return 1
  [ "$1" = "$expected" ] || return 1
  IFS= read -r -d '' cmd < /proc/$p/cmdline || return 1
  [ "$cmd" = {identity} ] || return 1
}}
identity || {{ print -r -- identity-mismatch; exit 41; }}
case "$state" in R|S|D|I) print -r -- "verified:$state"; exit 0 ;; esac
exit 43"#,
            pid = self.pid,
            started = self.started,
        );
        let output = client
            .shell(
                &command,
                4096,
                OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                },
            )
            .await?;
        if output.exit_code.is_some_and(|code| code != 0)
            || !output.stdout.starts_with(b"verified:")
        {
            return Err(Error::new(
                "process_identity",
                "无法确认本会话服务进程的身份。",
            ));
        }
        Ok(())
    }
}
