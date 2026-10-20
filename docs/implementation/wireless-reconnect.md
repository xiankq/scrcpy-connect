# 可信无线设备的候选地址与重连

已配对设备仍使用自己的设备 ID 和精确 GUID，网络地址只是当前连接位置。Runtime 监控保存同一可信服务的候选地址；Dart `ReconnectionCoordinator` 根据设备快照、事件、自动重连偏好和前后台状态调度单次连接，并持有退避计时。单次执行按候选依次尝试 Required TLS；首个地址不可达不直接结束整次重连，只在成功接入后持久化实际使用的地址和端口。已配对但没有保存连接端口的记录也可使用新发现的地址。

调度器通过 Runtime 租约登记所有者及尝试代次；释放、手动断开、忘记设备或身份变化后，旧尝试不能发布连接。手动断开同时关闭该设备自动重连。健康探测和旧连接清理仍由 Runtime 持有，新的自动连接必须先通过设备转换栅栏。USB 离线后须由用户重新允许系统访问，不安排网络自动重试。底层 `interop-adb` 不持有调度器或产品重连事件。

发现内容更新和 goodbye 会推进代际。连接在 TLS／元数据处理中跨越新一代发现结果时，成功和失败都不能再覆盖当前设备状态；包括最初还没有发现、正在尝试旧缓存地址的情况。同一地址撤销后再次出现也属于新代际。提交成功和授权失败均在取得设备操作锁、设备记录锁后核对发现代际，持发现读锁完成发布，避免旧地址的授权失败误关新地址的自动重连。

拒绝授权后停止自动重连，不降级到明文，也不继续尝试其他地址发送授权材料。发现只缓存已知的非 USB GUID，每个 GUID 最多八个活动服务，精确 GUID 实例优先。GUID 级 observed 标记记住撤销，不无限保存每个旧 fullname 的墓碑；全局单调修订号避免移除／重建的 ABA。忘记设备后下一轮监控回收其缓存。这个上限约束服务条目数，不替代底层 DNS-SD 接收队列或单个快照的边界。

## 配对完成后的候选地址

配对码/扫码成功后复用同一Required TLS候选遍历与成功准入路径，不先保存第一个未经验证的DNS-SD地址。浏览器保留到TLS/metadata发布，端口更新与goodbye继续推进代际；Dart ConnectionSetupCoordinator按配置最多重试三次发现代际，沿用显式原生操作租约。原生每次仅执行单代候选遍历；显式断开可取消发现，旧表单取消不清掉新操作。attemptId不得与已有设备ID冲突。

## 已执行证据与限制

`tests/mdns_reconnect.rs`用公开Runtime、真实多播DNS-SD及TLS/STLS/CNXN socket核对不可达首地址/第二地址成功、端口变更、goodbye、近似GUID、明文拒绝、旧握手和同端点ABA。旧实现曾发布缓存旧端口，新实现只发布当前已验证端点。

`device/pairing_tests.rs`另有真实watcher/TLS候选测试：第二地址、发现中取消、明文拒绝不落端点、发现更新/撤销后旧client不发布。它在内部发布接缝核验，不冒称同一次完整PAKE/metadata竞争。组播用例默认ignored，需显式运行：

```sh
cargo test -p interop-core --test mdns_reconnect -- --ignored --test-threads=1
cargo test -p interop-core --lib device::pairing_tests -- --include-ignored --test-threads=1
```

2026-10-18正式App/FRB/Rust在安全配置API36 AVD通过未授权拒绝、错码、PAKE、Required TLS及精确撤权后拒绝；范围和系统Settings竞争见[首次配对](first-pairing.md)。这是lab镜像/NAT手动连接，不是物理多地址Wi-Fi/OEM。IPv6 link-local scope、真实多网卡、Wi-Fi漫游和授权失败等待发布锁的精确交错仍未由该测试证明；静态锁序核对不当动态运行证据。
