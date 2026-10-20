# 跨目录名称搜索

文件页保留当前目录即时筛选，另由“搜索子文件夹”进入专用页。搜索固定设备与根目录；用户明确提交名称与类型，也可改为整个共享存储。修改条件不会将旧结果伪装成新查询；同名结果展示父目录，点击时由原文件/目录路由重新核验。

## 共享实现

Rust `files.search.start/get/cancel` 持有独立只读任务，Flutter协调一次可见搜索及迟到回执；不增加原生业务或被控APK。start发布searchId后开始BFS，get不触发重搜，cancel只作用于匹配设备的该searchId。离页若start尚未返回，迟到ID也会被精确取消。查询读取世代独立于任务世代，旧running快照不能覆盖较新的cancelled快照。

结果含固定根/query/filter、进度、匹配项、issues、complete及终态。过滤类型为全部、图片、视频、音频、文档、压缩包和文件夹；匹配文件名，不读取正文。Unicode匹配使用固定15.0异常casefold映射及Rust小写表，来源/生成方式记录于代码：官方[CaseFolding 15.0](https://www.unicode.org/Public/15.0.0/ucd/CaseFolding.txt)，SHA-256 `cdd49e55eae3bbf1f0a3f6580c974a0263cb86a6a08daa10fbf705b4808a56f7`；不是规范化/拼音/全文索引，也不宣称任意未来Unicode版本的完整映射。

Unicode数据的[版权与许可通知](../../crates/interop_core/src/LICENSE-UNICODE)随源文件保留；这不是新增原生库或运行时下载要求。

最多30秒、500匹配、50000检查项、2048目录、32层，每目录4096项；活动最多4条、历史最多16条。达到上限、权限/元数据失败、目录变化或无效编码均保留已匹配内容并说明未完成范围；取消不变成成功。终态历史可被后续搜索淘汰，进程重启不恢复搜索或自动扫描。

子符号链接不跟随；标准Android存储别名按明确规则允许。无效UTF-8名称不生成替换字符的可操作路径。每个目录入队后重验类型、扫描前后核对元数据；ADB按路径访问，不提供恶意并发替换下的事务隔离，不能将其解释成文件系统快照。

## 实际协议差异

某些adbd的LIST会把opendir权限失败返回空DONE，搜索先核验目录可读/可遍历；SYNC不足或拒绝时，`remote_fs`使用同一个描述符校验的临时原生元数据服务，保留逐项errno、64位字段、原始名称与截断状态。旧shell glob回退已被替换，不依赖设备存在find/stat等工具。查询文字从不拼入shell。

标准存储根别名和无效名称保护与文件/相册共用边界，见[被控兼容](android-target-compatibility.md#旧协议与文件服务)。元数据或权限未知不当空目录，根目录 `/` 不可因去尾分隔符变空路径。

## 可复现验收

```sh
env INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  cargo test -p interop-core --test file_search_android -- --include-ignored
# 以下 Flutter 命令进入 app/ 执行，Rust/Flutter在PATH，JDK21与Android SDK已配置。
cd app
env CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/file-search \
  flutter drive -d emulator-5554 --no-pub --driver=../tool/driver/file_search.dart \
  --target=integration_test/file_search_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=15556
```

保留的真实adbd用例覆盖跨目录同名、中文/引号/换行、casefold、筛选、无效UTF8、链接、上限、拒权、空目录、存储别名及取消隔离。2026-10-17双API36产品流程从真实文件页搜索/筛选/打开结果，独立核对原件与精确清理，截图已目视。

该样本不证明任意OEM权限、实时全文索引、恶意并发替换下的快照隔离、低内存或所有大目录性能；部分结果不能显示为完整无匹配。当前旧协议/元数据回退的证据另见[兼容验证](android-target-compatibility.md#验证证据)。
