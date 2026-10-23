# 跨目录名称搜索

产品入口与部分结果呈现归[内容规格](../../designs/prod/content-and-transfer.md)。Dart device_files.RemoteFiles持有BFS、筛选、取消与快照，DeviceRuntime分派search.start/get/cancel，Rust只提供typed stat/list事实；共享预算与符号链接规则见[能力包](../../packages/device_files/README.md)。

start建立searchId，get只读快照，cancel核对设备/ID；离页取消精确搜索（含迟到start回执），进程重启不恢复。名称按Dart toLowerCase后contains，不做全文/拼音/Unicode casefold；打开结果重新核验。搜索另限500匹配、2048目录、8MiB结果；达到任一预算/错误保留部分结果。旧协议目录事实见[兼容](android-target-compatibility.md#旧协议与文件服务)。

当前所有者及原生组装证据归[device_files验收](../../packages/device_files/VALIDATION.md)。页面入口为app/integration_test/file_search_test.dart及tool/driver/file_search.dart，从app按[隔离规则](validation.md#复现入口)运行。2026-10-17双API36 AVD曾核对搜索/筛选/打开，但早于Dart所有者迁移；OEM、拒权、大目录和进程恢复仍需各自证据。
