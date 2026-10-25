import 'control.dart';
import 'event_observer.dart';
import 'models.dart';

/// 由宿主唯一原生库注入的传输接口。共享同一 ADB 连接注册表，不自行载入第二份原生库。
abstract interface class NativeScrcpyApi {
  /// 仅登记本机捕获；返回后才能开始远端工作，句柄从此可以被 stop 撤销。
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  });
  Future<ScrcpySessionInfo> startSession(String sessionId);

  /// generation 属于本机渲染器；获取描述不分配媒体字节缓冲或停止租约。
  Future<ScrcpySessionInfo> inspect(String captureRef, {int generation = 1});

  /// 撤销精确捕获，等待本机清理及本次受监督主进程的退出证明。
  /// 启动结果未知或远端核验失败须保留原句柄供重试；不承诺子进程或系统设置恢复。
  Future<void> stopSession(String sessionId);

  /// 回执明确返回队列准入、写入或剪贴板 ACK；宿主可对输入等待写入，不能将准入虚报为写入。
  /// StartApp 的写入回执不证明应用已打开。
  Future<ScrcpyControlReceipt> sendControl(
    String sessionId,
    ScrcpyControlMessage message,
  );

  /// 每次调用返回独立可重试的观察者；订阅取消与 close 只释放观察，不停止来源。
  ScrcpyEventObserver openEvents(String captureRef);
}

/// 同一宿主的连接级捕获恢复能力；连接句柄必须仍拥有当前登记的权限。
abstract interface class NativeScrcpyConnectionApi {
  /// 取消调用时已登记的捕获并等待实际清理，不关闭连接或取消随后新建的捕获。
  /// 清理未确认时抛出异常并保留原生所有权，调用者可用当前连接句柄重试。
  Future<void> drainConnection(String connectionId);
}

/// 分阶段启动以及原始执行事实；不含产品窗口和任务策略。
abstract interface class NativeScrcpyStagedApi {
  Future<ScrcpySessionInfo> startControl(String sessionId);
  Future<ScrcpySessionInfo> awaitMedia(String captureRef, {int generation = 1});
  Future<ScrcpyProcessInfo> processInfo(String captureRef);
}

/// 按当前连接权限查询精确捕获的来源事实；未知或已释放来源必须明确失败。
abstract interface class NativeScrcpySourceStatusApi {
  Future<ScrcpySourceStatus> sourceStatus({
    required String connectionId,
    required String captureRef,
    required String sourceId,
  });
}
