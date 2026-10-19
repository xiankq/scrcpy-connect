# 可信无线设备的候选地址与重连

已配对设备仍使用自己的设备 ID 和精确 GUID，网络地址只是当前连接位置。后台监控保存同一可信服务的候选地址，按候选依次尝试 Required TLS；首个地址不可达不直接结束整次重连，只在成功接入后持久化实际使用的地址和端口。已配对但没有保存连接端口的记录也可使用新发现的地址。

发现内容更新和 goodbye 会推进代际。连接在 TLS／元数据处理中跨越新一代发现结果时，成功和失败都不能再覆盖当前设备状态；包括最初还没有发现、正在尝试旧缓存地址的情况。同一地址撤销后再次出现也属于新代际。提交成功和授权失败均在取得设备操作锁、设备记录锁后核对发现代际，持发现读锁完成发布，避免旧地址的授权失败误关新地址的自动重连。

拒绝授权后停止自动重连，不降级到明文，也不继续尝试其他地址发送授权材料。发现只缓存已知的非 USB GUID，每个 GUID 最多八个活动服务，精确 GUID 实例优先。GUID 级 observed 标记记住撤销，不无限保存每个旧 fullname 的墓碑；全局单调修订号避免移除／重建的 ABA。忘记设备后下一轮监控回收其缓存。这个上限约束服务条目数，不替代底层 DNS-SD 接收队列或单个快照的边界。

## 证据与未覆盖项

[mdns_reconnect.rs](../../crates/interop_core/tests/mdns_reconnect.rs) 通过公开 Runtime、真实多播 DNS-SD、TLS/STLS/CNXN socket 检查发布状态。首个不可达地址／第二地址成功、端口变更、goodbye、近似 GUID 拒绝、禁止明文、旧握手迟到、先缓存后发现更新、先缓存后撤销及同端点 ABA 共七项串行通过，最终 89.08 秒。缓存地址先启动后出现新发现的新增测试，修复前确实发布了旧端口，修复后只发布新端口。

```sh
env CARGO_BUILD_JOBS=2 \
  cargo test -p interop-core --test mdns_reconnect -- --ignored --test-threads=1
```

这不是物理 Wi-Fi 换网或 OEM 验收。IPv6 link-local scope、真实多网卡与 Wi-Fi2 仍待验证；首次配对缺口的修复与验证见下节。授权失败恰好等待内部发布锁的时间窗口没有公共 API 可稳定占锁，本批通过统一锁序与读锁作用域核对，不能称该精确交错已动态通过。完整 ADB／无线任务继续开放。

## 首次配对完成后的候选地址（2026-10-18）

原实现完成PAKE后只取首个DNS-SD地址，并在TLS成功前保存它。真实多播／TLS回归
先复现connected=false及坏地址192.168.0.0落库，合法第二地址未被连接。现在复用
Required TLS候选遍历及成功发布路径；发现浏览器保留到TLS／元数据发布，端口更新
和goodbye继续推进代际。发现开始前即注册同一设备操作token，显式断开能取消发现，
最多三次代际重试不会替换并取消自己的token。端点只在成功接入时保存；取消旧表单
不清除新操作。配对attemptId禁止与已有设备ID混用，避免两个取消入口相互覆盖。

[首次配对边界测试](../../crates/interop_core/src/device/pairing_tests.rs)最终五项
48.51秒通过：真实DNS-SD首地址不可达／第二地址TLS成功、发现中取消且不再建TCP、
明文CNXN拒绝且端点不提交、实际发现更新／goodbye后旧TLS client不能发布，以及
不发网络的attemptId校验。四项多播用例显式执行，默认ignored不算执行证据。
代际测试使用真实watcher和真实TLS client，但在内部发布接缝检查，不声称完成了
整个PAKE与元数据竞争的同一次交错。中间两次泛型推断编译失败保留，不当产品红测。

```sh
env CARGO_BUILD_JOBS=2 cargo test -p interop-core --lib \
  device::pairing_tests -- --include-ignored --test-threads=1
```

最终Core181 passed／53 ignored、既有七项mDNS回归及Core all-targets clippy
`-D warnings`通过。原件分别在`/tmp/connect-pairing-candidates-{final-host-r3,
core-regression,mdns-regression,clippy}.log`；红测为
`/tmp/connect-pairing-candidates-red.log`，只读review未报告新增确定问题。

正式App／FRB／Rust在API36安全AVD链路69秒通过：初次未授权拒绝、错码拒绝、实际
PAKE、独立Required TLS连接、IAdbManager按精确产品身份撤权后拒绝旧身份；原系统
其他信任保留，记录／fixture／forward清理均确认，hostErrors为空。截图目视确认
连接工作区及撤权后的授权失败入口，原件`/tmp/connect-e2e/pair-candidates-product/`。
这是调试型lab镜像与NAT下的手动连接，不是物理多地址Wi-Fi／OEM验收；多播候选由
上述主机真实协议边界覆盖。两份scrcpy JAR未改，这个修复不需要重建服务端。


Core针对iOS／macOS／Windows MSVC交叉check2.33／2.14／2.28秒及Rust格式检查通过，
不是对应Flutter宿主整包。最终arm64签名产物及正常App恢复／清理见
[打包历史记录](android-packaging.md)；当前结构与依赖见 [架构](architecture.md)。
