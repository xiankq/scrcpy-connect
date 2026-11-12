//! 拉取式消费者的读取责任与闲置期限；一次锁空闲不代表消费者已经离开。
use std::sync::Mutex;
use std::time::Duration;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

pub(crate) struct ConsumerActivity {
    state: Mutex<State>,
}

struct State {
    readers: usize,
    last_read: Instant,
}

impl ConsumerActivity {
    pub(crate) fn new() -> Self {
        Self {
            state: Mutex::new(State {
                readers: 0,
                last_read: Instant::now(),
            }),
        }
    }

    /// 读取等待也属于活跃消费；future 被取消或返回后才开始计算新的闲置期限。
    pub(crate) fn reading(&self) -> Reading<'_> {
        self.state.lock().expect("消费者活动").readers += 1;
        Reading(self)
    }

    /// 在同一短锁内核验期限并撤销操作，不能让新读取越过已经作出的回收决定。
    /// now 由调用方采样，便于以确定时刻核验到期边界，不改变真实清理的完成要求。
    pub(crate) fn cancel_if_idle_at(
        &self,
        now: Instant,
        idle: Duration,
        cancellation: &CancellationToken,
    ) -> bool {
        let state = self.state.lock().expect("消费者活动");
        if cancellation.is_cancelled() {
            return true;
        }
        if state.readers != 0 || now.saturating_duration_since(state.last_read) < idle {
            return false;
        }
        cancellation.cancel();
        true
    }
}

pub(crate) struct Reading<'a>(&'a ConsumerActivity);

impl Drop for Reading<'_> {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().expect("消费者活动");
        state.readers -= 1;
        state.last_read = Instant::now();
    }
}
