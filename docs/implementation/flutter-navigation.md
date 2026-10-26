# 页面与路由

## 文件布局

pages按业务父子关系组织，有子页的入口放index。文件名使用pages以下完整目录链加 `_page.dart`；专属组件放当前widgets，共享业务组件放最近公共父级。通用控件归设计系统，业务执行归对应模块。

## 页面身份

路由以 `app/lib/router/app_router.dart` 为准，跨页使用生成的typed route。`RouteResourceResolver` 从当前记录核验设备、任务及会话；URL和extra不授予授权。

新远控需要短暂RemoteLaunchIntent；意图丢失提供重新打开入口，不从URL自动创建会话。既有远控同时匹配deviceId和sessionId。统一连接表单持有草稿与attempt，切模式后旧回执不能导航。

## 生命周期与返回

三标签shell保留各自历史，全屏远控覆盖根Navigator。主题、事件与router刷新保留同一远控子树。遮挡/后台只暂停；明确关闭或路由移除释放本窗口输入、声音租约和精确session，真实手机应用任务保留。

目录选择返回String?，导入返回bool；局部弹层使用自己的Navigator。分享确认/取消匹配精确shareId，连接成功替换表单。

## 当前设备归属

`VisibleDeviceFocus` 在路由可见、前台且设备已核验时声明焦点，撤回只影响自己的声明；帧回调重验epoch与页面身份。远控还需会话和像素核验。焦点不改变传输或交付的固定来源。

appDependenciesProvider注入真实请求、事件及关闭接口，AppController发布不可变快照，销毁时取消订阅。SessionViewRegistry通过独立lease管理窗口，帧事件只发往所属页面。

生成及插件检查见[工具入口](../../scripts/README.md)，产品返回与关闭规则见[交互规则](../../designs/prod/interaction-rules.md)。
