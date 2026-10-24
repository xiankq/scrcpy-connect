# 跨目录名称搜索

产品入口与部分结果呈现归[内容规格](../../designs/prod/content-and-transfer.md)。应用 Dart `FileCatalog` 持有 BFS、筛选、取消与快照，`FileCommands` 将 search.start/get/cancel 映射到目录所有者，Rust 只提供类型化 stat/list 事实；共享预算与符号链接规则见[文件所有者](file-ownership.md)。

start建立searchId，get只读快照，cancel核对设备/ID；离页取消精确搜索（含迟到start回执），进程重启不恢复。名称按Dart toLowerCase后contains，不做全文/拼音/Unicode casefold；打开结果重新核验。搜索另限500匹配、2048目录、8MiB结果；达到任一预算/错误保留部分结果。旧协议目录事实见[兼容](android-target-compatibility.md#旧协议与文件服务)。

当前所有者及原生组装证据归[文件所有者验收](file-ownership-validation.md)。页面入口为app/integration_test/file_search_test.dart及tool/driver/file_search.dart，从app按[隔离规则](validation.md#复现入口)运行。2026-10-17双API36 AVD曾核对搜索/筛选/打开，但早于Dart所有者迁移；OEM、拒权、大目录和进程恢复仍需各自证据。
