# 被控执行产物

修改前读取对应 [vendor](vendor/README.md)、[companion](companion/README.md) 或 [helpers](helpers/README.md) 构建说明。

源码、manifest、固定产物与共享 assets 同步更新；应用只向能力包提供校验过的字节。协议变更同时核对调用端；低版本兼容须检查真实方法签名与类加载，不只降低编译目标。

部署与回收仅操作本次拥有的目录、流和进程；退出未确认保留清理责任。受控二进制、许可证和对应源码归档属于输入，按[工具链](../docs/implementation/repository-tooling.md)保留。
