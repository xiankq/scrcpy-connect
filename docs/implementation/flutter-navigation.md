# Flutter 页面与路由

产品行为归[交互规则](../../designs/prod/interaction-rules.md)。生产入口为app.dart的MaterialApp.router；main初始化失败使用独立StartupErrorPage，不依赖未建立的路由/连接服务。

## 文件布局

pages按业务父子目录组织：有子页的入口放index，叶页直接放业务目录。文件名为pages以下完整目录链下划线连接加_page.dart（包含index）。专属组件放当前widgets，跨子页放最近共同业务widgets，不引用其他页面私有组件。通用控件归 `packages/design_system`，应用呈现与页面状态归 `app/lib/presentation`，业务执行按连接、文件、媒体等职责组织；typed路由及资源解析归router。只为生成文件使用.g.dart part。

设置归settings、连接建立归connection、工作台/远控归devices/workspace、连接配置/数据/能力/诊断归devices/details（无独立详情页）、接收导出归transfers/details。目录表达业务归属，多入口复用同一实现，迁移不改变typed route身份。

## 页面身份

完整图及地址由 `app/lib/router/app_router.dart` 的TypedGoRoute/TypedStatefulShellRoute声明，生成文件与源码同步；不在文档再列一份路由表。生产直接使用typed route，navigation.dart只保留显式远控启动、typed返回和回设备页。

`RouteResourceResolver` 按路由参数从当前权威设备/任务/会话重新核验目标；文件路径按当前清单核对。地址/ID不授予授权，缺失记录呈现可重试错误及返回入口，不强转extra。新远控只接受短暂RemoteLaunchIntent；意图丢失提供重新打开入口，URL/进程恢复不自动创建会话。已有远控必须同时匹配deviceId/sessionId。

兼容地址保留：details、tools、sessions回同设备工作台；设备adb-key回连接配置；settings/activities回设备列表；wireless/form/usb/qr呈现统一添加表单的预选形式。连接草稿与尝试身份由统一表单持有，切换后旧扫码/USB/发现回执不得导航或改新形式；重新授权与补连接端口保留原deviceId及授权身份。

## 生命周期与返回

三标签StatefulShell保留分支和返回历史，根路由用MaterialPage；全屏远控覆盖根Navigator。主题、事件、router.refresh保留同一路由远控子树及首次打开决定。明确关闭/路由移除释放本窗口输入和呈现，停止精确session；真实应用任务留给手机。遮挡/后台只暂停，挂起暂停不得阻止明确关闭；终止ID不重新附着或重放初始操作。

目录选择返回String?（取消null），导入成功返回bool；分享确认/取消消费准确shareId，提交携带它保留传输源。连接成功typed替换表单；弹层/选择器使用局部Navigator.pop。

## 状态与依赖所有权

AppController为生成Notifier，AppState深冻结；页面select所需字段，服务snapshot读取。appDependenciesProvider在根ProviderScope注入真实request/events/close，controller以ref.watch持有，onDispose取消唯一订阅并关闭transport。异步回执受请求序号/生命周期约束；session.frame只发给所属页面流，不更新全应用快照。

`clipboardCoordinatorProvider` 拥有 timer、事件和生命周期观察，并在销毁时清理。文本控制器归页面；`SessionViewRegistry` 登记窗口租约，串行处理可见性与关闭操作，页面通过 `SessionViewLease` 取得和释放自身呈现资格。恢复边界归[状态恢复](state-recovery.md)。

## 当前设备归属

设备核验后才由VisibleDeviceFocus依据ModalRoute、生命周期与核验状态声明焦点；失去资格只撤回自己的声明。post-frame重查epoch、device、mounted及实际route，旧页不能清空新页焦点。Remote使用更严格的会话/像素核验，不被共享包装器提前激活。

## 生成与分析

从workspace根运行 `dart run build_runner build --workspace`，一致性检查加 `--only-check`；版本/兼容组合归[工具链](repository-tooling.md)。app/build.yaml仅为生成文件忽略nullable Object extra的冗余cast。根analysis plugin启用riverpod_lint，app继承配置；不恢复旧custom_lint。

## 验证

app/test中的router_test.dart覆盖分支/ID/返回、远控重建/释放、typed结果及表单替换；app_provider_test.dart覆盖冻结、晚回执、transport及帧隔离。设备运行按[验证入口](validation.md#复现入口)另行执行。
