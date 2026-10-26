---
status: accepted
---

# 显式原生组合与独立工具测试环境

`AdbHost` 显式接收 bindings：独立用户选择独立实现，scrcpy 宿主使用同库实现，避免重复连接、跨动态库传对象及应用重复携带 ADB 栈。独立桥保留；build/link hooks 按初始化入口可达性决定发布，信息缺失则保留。代价是分别维护独立与组合使用。

工具测试在独立 `test/host/` Dart 环境及锁文件中运行。Flutter 固定测试依赖与工具 analyzer 不能共用解析，继续用 Flutter runner 会编译无关原生 hooks；隔离环境避免 override 改写应用依赖。构建规则见[工具链](../implementation/repository-tooling.md)。
