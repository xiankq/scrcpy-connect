# device_preferences

纯 Dart 本机偏好所有者：默认值合并、校验、历史迁移、更新/重置、revision 冲突检查与原子文件替换。画质默认值由调用方从画质能力包注入，避免偏好包依赖播放器或原生运行时。

`DevicePreferences.open` 首先读取独立 `preferences.json`。不存在时才只读同目录旧 `devices.json` 的 `version`/`settings`；v1 按完整旧 balanced 签名迁移网络默认，v2 保留明确选择；两者都清理已退役全局设置。验证后先写同目录临时文件并 flush，再 rename 原子替换。成功后新文件成为唯一偏好来源，旧设备、授权摘要和私钥文件均不由本包改动。损坏或较新版本失败并保留原字节，不静默重置。

新格式：`{"format":"scrcpy-connect-preferences","version":1,"revision":1,"settings":{...}}`。同一 isolate 的实例及其他进程写入由同目录锁文件与本 isolate 队列串行，更新对 revision 比较后提交；冲突不会覆盖其他写入，调用方可读取最新快照后重新确认。偏好所有者固定在一个 isolate，其他 isolate 通过消息请求该所有者；POSIX 文件锁不能保护同进程其他 isolate 的独立写入。已提交数据用不可变快照公开。正常重启恢复已提交 revision；文件 flush + 原子 rename 不承诺设备断电后的目录元数据持久性。

`PreferenceSchema.executionMirror` 仅输出原生执行所需的 ADB burst、画质及保持唤醒配置。授权身份、设备恢复和连接生命周期不属于此包。元数据导入清空原设备 ID 下的偏好，因为设备恢复会分配新身份；设备/授权恢复由应用适配器交原模块处理。

应用适配器先持久化偏好，再应用执行镜像。执行回执丢失时保留已保存值并报告 saved=true/applied=unknown；重启或显式 reconcile 重新投影镜像，不能把未知结果当失败回滚或重试设备导入。

文件替换使用 Dart `File.rename`：Windows SDK 原生实现调用带 REPLACE_EXISTING/WRITE_THROUGH 的 MoveFileExW，参见 [Dart SDK 文件实现](https://github.com/dart-lang/sdk/blob/main/runtime/bin/file_win.cc#L726)。实际偏好文件测试目前在 Linux 主控执行，Windows/Apple 的本模块设备运行仍待验。
