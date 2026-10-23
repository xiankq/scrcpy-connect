# device_preferences

纯 Dart 偏好所有者，负责默认值、校验、迁移、更新/重置、revision 冲突检查和原子持久化。画质默认值由调用方注入。

`DevicePreferences.open` 读取 `preferences.json`；仅在文件不存在时只读迁移旧 `devices.json` 的设置，不修改设备身份或授权文件。损坏或较新格式保留原字节并失败。更新按 revision 比较后提交不可变快照，冲突由调用方重新确认。

同一私有目录固定一个 isolate 所有者，其他 isolate 通过消息调用；锁文件不能代替同进程跨 isolate 的所有权约束。写入采用 flush 与原子 rename，未承诺断电后的目录持久性。

`PreferenceSchema.executionMirror` 只投影原生执行配置。应用先保存再应用；回执丢失保留 `saved=true/applied=unknown`，由重启或显式 reconcile 恢复投影，不回滚已保存值。授权与设备恢复归原模块。文件测试已在 Linux 执行，Windows/Apple 运行待验。
