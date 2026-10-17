# 跨目录名称搜索

文件页保留当前目录即时筛选，另由“搜索子文件夹”进入专用页。搜索固定设备与根目录；用户明确提交名称与类型，也可改为整个共享存储。修改条件不会将旧结果伪装成新查询；同名结果展示父目录，点击时由原文件/目录路由重新核验。

## 共享实现

Rust `files.search.start/get/cancel` 持有独立只读任务，Flutter协调一次可见搜索及迟到回执；不增加原生业务或被控APK。start发布searchId后开始BFS，get不触发重搜，cancel只作用于匹配设备的该searchId。离页若start尚未返回，迟到ID也会被精确取消。查询读取世代独立于任务世代，旧running快照不能覆盖较新的cancelled快照。

结果含固定根/query/filter、进度、匹配项、issues、complete及终态。过滤类型为全部、图片、视频、音频、文档、压缩包和文件夹；匹配文件名，不读取正文。Unicode匹配使用固定15.0异常casefold映射及Rust小写表，来源/生成方式记录于代码：官方[CaseFolding 15.0](https://www.unicode.org/Public/15.0.0/ucd/CaseFolding.txt)，SHA-256 `cdd49e55eae3bbf1f0a3f6580c974a0263cb86a6a08daa10fbf705b4808a56f7`；不是规范化/拼音/全文索引，也不宣称任意未来Unicode版本的完整映射。

Unicode数据的[版权与许可通知](../../crates/interop_core/src/LICENSE-UNICODE)随源文件保留；这不是新增原生库或运行时下载要求。

最多30秒、500匹配、50000检查项、2048目录、32层，每目录4096项；活动最多4条、历史最多16条。达到上限、权限/元数据失败、目录变化或无效编码均保留已匹配内容并说明未完成范围；取消不变成成功。终态历史可被后续搜索淘汰，进程重启不恢复搜索或自动扫描。

子符号链接不跟随；标准Android存储别名按明确规则允许。无效UTF-8名称不生成替换字符的可操作路径。每个目录入队后重验类型、扫描前后核对元数据；ADB按路径访问，不提供恶意并发替换下的事务隔离，不能将其解释成文件系统快照。

## 实际协议差异

AOSP设备可能因shell创建的链接无法被adbd读取元数据而使扩展LIST整体errno13；另有LIST在opendir权限拒绝时返回空DONE。现先确认目录可读/可遍历，优先Sync；失败才使用固定shell glob、NUL记录和逐项lstat回退。搜索文字从不进入shell，根完整quote，名称含引号/换行仍原样保持；stderr、退出码、数量和无法解析元数据均保守报告partial。不是拼接find命令搜索。

独立review还发现`/`去尾分隔符后使权限检查变空路径；真实公开用例先红，保留绝对权限根后绿。仅glob前缀去尾分隔符。普通主控不申请额外调试权限，全部读取仍限于已授权ADB能访问的内容。

## 可复现验收

```sh
rtk proxy env INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  cargo test -p interop-core --test file_search --test file_search_android -- --include-ignored
# 工作目录 apps/connect，Rust/Flutter在PATH，JDK21与Android SDK已配置。
rtk proxy env CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/file-search \
  flutter drive -d emulator-5554 --no-pub --driver=test_driver/file_search.dart \
  --target=integration_test/file_search_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=15556
```

普通Runtime回归验证输入/空查询/无连接/记录过期；真实adbd回归覆盖同名跨目录、中文/引号/换行、大小写、筛选、非法UTF-8、链接、500匹配、权限、空目录、标准别名、根目录、取消隔离与断连。产品E2E通过公开文件操作建立唯一夹具，再从真实文件页搜索、筛选、打开详情和精确清理；host只在所有必要回执齐备时确认。结果与实际失败见[验收记录](validation.md)。

这不关闭文件管理任务：目录/批量系统交付、提供方与空间/撤权矩阵、可恢复传输意图、媒体索引分页和完整页面/无障碍仍需继续。Pencil源稿已补条件、进行中和主动停止保留结果三个代表状态，不把静态状态当作完整交互验收。
