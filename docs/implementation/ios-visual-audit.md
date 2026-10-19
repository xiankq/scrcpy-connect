# iOS Liquid Glass 逐页视觉审计

> 此文件保留逐页视觉审计的历史检查与证据，后续修订不能把前轮判断改成当时已通过。当前视觉规范见 [design.md](../../designs/design.md)，产品行为见 [交互规则](../../designs/prod/interaction-rules.md)，最终测试/真实 GPU 与产品回执索引见 [产品验收记录](product-refinement.md)。

审计日期：2026-10-19。源稿：`designs/mobile.pen`。当前为101个独立页面：99手机、2大屏。本文件保留初始94页问题定位，并记录后续逐页目视、补稿、源码对照和截图证据。最终全量、Android产品流程及9张GPU图有限人工复核已回填；原生等效性、完整动态与性能仍保留证据边界。

## 证据与范围

- 初始通过 Pencil MCP Get 结构扫描 **94页：92手机、2大屏**，当时截图抽看18页。18页是历史阶段计数，已经由下述逐页截图复核覆盖，不再作为当前覆盖上限。
- 后续原92手机页按画布y、x顺序分成两批；`ios_material_system`与`ios_page_audit`各实际TakeScreenshot目视46页。新增7个独立手机页也逐张截图检查；2大屏页有实际截图复核回执。合计101页均有静态截图查看证据，**不代表所有业务状态或最终GPU材质通过**。
- 2大屏回执覆盖侧栏＋真实设备列表、侧栏＋单设备工作台及无重叠；其后共享材质再次调整，不把此前截图当成最终材质版本的复验。
- 已静态对照`lib/pages`下全部 **41个`*_page.dart`**。页面代理已补齐41页的浅/深色夹具和5个额外状态，共92张，另加4张窄屏／横屏2倍文字根导航，当前目录 **`/tmp/connect-ios-review`共96张PNG**。对应关系见本文41页表，完整临时清单见[页面回执](/tmp/connect-ios-review/page-audit.md)。
- 材质代理逐张查看过96张的前一捕获版本；后续页面代理已重拍当前96张，特别等待图片首帧并检查gallery/media_preview的RawImage非空，实际打开确认最新浅/深媒体有照片。**未将前一版的逐张查看冒充当前96张再次全部人工验收**。
- 页面代理定向回归9文件33项通过，见[日志](/tmp/ios-followup-final.log)；当前96图捕获测试1项通过，见[捕获日志](/tmp/ios-capture-followup.log)。最终根应用全量323个非hidden项成功；之后两处纯lint修复又完成3文件13项（含96图重拍），静态分析与生成一致性均通过，详见后文最终回执。
- Widget截图走测试降级渲染，不证明Android Impeller折射。独立[GPU harness](../../integration_test/glass_material_test.dart)与[严格driver](../../tool/driver/glass_material.dart)已经交付，主代理已完成9场景shader采集与严格driver校验；材质代理已逐张查看9图并给出有限光学结论；原生级动态、性能、多路真实媒体与物理设备体验仍单列待验。早期`/tmp/connect-refined-ui`仅作历史对照。
- 主代理最新源稿回执为**101页、30母组件、186变量**：新增共享sidebar `UMqM7`、删除闲置母组件`M7YtSe`；18处旧blur统一为`assets/liquid-glass.glsl`，Pencil shader实际编译成功。当前Get仅有`uESR9`工作台完整内容相对scroll-viewport的有意滚动裁剪；`W7Lua`降低透明度页意外继承的导航shader已改为全实色，Get确认无shader并保存；没有旧panel/reflection六变量引用。`sepTa/H0TFx/DtZbX`更新后已实际查看，没有在这些截图中发现破布局；这是Pencil静态光学表达，不能称与Apple原生像素一致或当作Flutter GPU通过。

用户最新纠正：**“黑色的主题色不要改，我说的是点缀色。”黑白主题及黑色主动作保留**；亮色仅用于图标、连接状态、警告、危险等有明确语义的点缀。当前规范与实现已按此保留主题；最终以 [design.md](../../designs/design.md) 为唯一规范来源。早期将黑色本身列为缺陷、建议全蓝主题的判断已撤回。规范变更不等于全部实例和实现已复验，本文不建立新的颜色、尺寸或光学参数表。

用户要求：**删除所有页头和普通列表项二级描述，保留状态正文**。共享PageFrame、ActionRow、ChoiceRow和普通ListTile的描述型subtitle已清理，手工特例按逐页审计处理。设备/任务当前状态、错误与校验、进度、通知正文、原文件归属、来源目标核对属于实际内容；应按语义处理，不能批量删除全部小字。

## 问题码与处理方向

| 码 | 初始发现 | 处理方向与证据边界 |
| --- | --- | --- |
| A | 主动作形态复验点：部分满宽胶囊视觉体积过粗、层级重复或与邻页不一致 | 保留黑白主题与黑色主动作；只检查宽度、厚重程度、密度和层级。表内仅有A时不代表已证实该按钮有缺陷 |
| B | 选中形态复验点：密集胶囊、厚重嵌套或同类页面不一致 | 黑色selected本身不是问题；按现行组件规则检查密度、比例、同层关系，避免把所有选中态强行改蓝 |
| C | 手写旧页头与共享页头高度、字号、间距不一致 | 删除二级描述后统一紧凑标题与安全区节奏，重新测量容器 |
| D | 真正浮动工具为实体白块／深灰块，缺少背景透入 | 只在导航、工具、菜单、sheet采用统一玻璃材料；普通内容维持中性实体材料 |
| E | 页头、列表或独立母组件仍有二级描述 | 清理共享组件及手工特例，收紧删除后留白；状态正文保持 |
| F | 装饰琥珀渐变 | 删除装饰底，采用中性条件区与语义选中规则 |
| G | 抽屉固定高度明显超过内容 | 内容自适应并限制最大高度，保留滚动与底部可达 |
| H | 大屏页独立手写且与实现结构脱节 | 明确共用材料、控件与响应布局；并行窗口能力另行验证 |
| J | 标题、筛选与内容明确重叠 | 修复布局流和约束后截图复验 |
| R | 未发现可单独归类的结构异常，仍需最终视觉复验 | 不以此码宣称已验收；检查现行材料、文案简化与动态行为 |

以下问题码保留初始发现，不再自动表示当前仍有缺陷。各页已完成静态截图查看，具体修复与仍待验证事项见后文回填。A/B只针对形态与一致性，黑色主题本身不构成不通过；“已目视”不等于动态、业务或四端验收通过。

## 原94个设计页逐页清单（初始定位＋后续目视）

### 设备列表：7 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| lUDPa | 设备 | A 添加；B 导航；E 设备卡辅助信息 | 已目视；动态另验 |
| tSC6u | 无设备 | A 添加；B 导航；E 独立空态说明 | 已目视；动态另验 |
| OxyeM | 深色外观 | A/B反白版本的体积与嵌套层级复验；玻璃层次偏弱 | 已目视；动态另验 |
| W7Lua | 降低透明度 | A/B；关闭模糊为合理辅助变体，不应强行恢复透明 | 已目视；动态另验 |
| HvaW2 | 检查连接中 | A/B；E 手工说明；保留真实检查状态 | 已目视；动态另验 |
| oHSUW | 全部离线 | A/B；E 设备卡辅助信息；保留离线状态 | 已目视；动态另验 |
| lj24R | 搜索无结果 | A/B；添加入口重复强调 | 已目视；动态另验 |

### 添加与发现：4 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| W3GRn | 添加设备 | E 内容行描述；底部独立说明与主列表区别处理 | 已目视；动态另验 |
| c0wxY | 开启无线调试 | A；E 内容行描述 | 已目视；动态另验 |
| h5JZfa | 未发现设备 | A；E 反馈与列表各有描述 | 已目视；动态另验 |
| yMlVd | 附近设备 | E；与主设备列表的选择与状态规则统一 | 已目视；动态另验 |

### 无线连接与配对：9 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| XQZRD | 使用配对码 | A；表单标签、配对端口与连接端口不可因精简而混淆 | 已目视；动态另验 |
| HevUb | 需要重新授权 | A；E；授权状态保留为正文 | 已目视；动态另验 |
| YvzMk | 手动连接 | A；独立辅助说明 | 已目视；动态另验 |
| E0CAl | 端口格式错误 | 禁用态有区分；错误提示不属于普通列表二级描述 | 已目视；动态另验 |
| gOwYI | 配对码已失效 | A；长动作文案密度偏高 | 已目视；动态另验 |
| G4CpTk | 扫码配对 | 独立说明；二维码及使用方式属于功能内容 | 已目视；动态另验 |
| pFGBZ | 已配对，尚未连接 | E；保留未连接与禁用态语义 | 已目视；动态另验 |
| xq5If | 正在连接 | E；检查中、取消后的真实状态需保留 | 已目视；动态另验 |
| OpFKk | 旧版 TCP-IP | A；新增表单也要纳入相同布局与输入规则 | 已目视；动态另验 |

### USB连接与授权：5 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| OxUaB | USB连接 | A；E 三条内容行 | 已目视；动态另验 |
| WMggr | 允许USB访问 | A；系统弹窗示意与产品控制层区分 | 已目视；动态另验 |
| ONn92 | 在手机上允许调试 | A；核对和授权条件为正文，不能全部去掉 | 已目视；动态另验 |
| w38WDx | USB授权未完成 | A；独立辅助说明 | 已目视；动态另验 |
| vPWPs | 从USB转为无线 | A/E；保留转换条件 | 已目视；动态另验 |

### 设备工作台与管理：8 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| nqQEb | Pixel 9 Pro | A；E Hero；正文超出滚动视口为有意滚动，不作为损坏 | 已目视；动态另验 |
| TMxVJ | 设备详情 | 开关与其他页面统一；黑色开关本身不是问题；E 独立母组件 | 已目视；动态另验 |
| eDTbS | 设备名称 | A；独立辅助说明 | 已目视；动态另验 |
| q3bM72 | 连接方式 | E 内容行；连接路径与重建状态保持明确 | 已目视；动态另验 |
| eWu3m | 连接诊断 | A；检查结果含手工正文 | 已目视；动态另验 |
| Txxv0 | 移除此设备 | A；危险动作与普通主动作区别表达 | 已目视；动态另验 |
| I6WG6Q | 断开设备 | A；与移除的严重程度区分 | 已目视；动态另验 |
| zyRl5 | 需要重新授权 | A/E；恢复记录不等于恢复授权身份 | 已目视；动态另验 |

### 手机与应用：12 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| tbWkA | 手机应用 | C/E；手写图标网格的背景与文字节奏统一 | 已目视；动态另验 |
| aVxBi | 独立应用·移动端全屏 | R；退出控件已有玻璃结构，远端原应用不染成主控主题色或点缀色 | 已目视；动态另验 |
| iEvoR | 窗口切换 | C/E；手工状态摘要独立 | 已目视；动态另验 |
| DtZbX | 全屏整机控制·退出按钮展开 | R；真实背景下检查退出控件可见性 | 已目视；动态另验 |
| HjBtR | 资源不足 | A；共用玻璃面板与来源关系 | 已目视；动态另验 |
| D5Cjet | 全屏控制·拖拽退出按钮 | R；静态稿不能证明拖拽、吸附和释放行为 | 已目视；动态另验 |
| D3HWzx | 全屏控制·右侧吸附收起 | 初始收起态缺少展开态模糊，检查材质连续性与可访问热区 | 已目视；动态另验 |
| P8F1YG | 全屏控制·左侧吸附收起 | 同右侧收起态，检查左右对称与安全区 | 已目视；动态另验 |
| Nph5q | 继续手机上的应用 | A/E；迁移提示属于真实条件 | 已目视；动态另验 |
| XvviW | 屏幕与输入工具 | A/E；工具和控制会话归属保持明确 | 已目视；动态另验 |
| tch6A | 应用打开方式 | C/E；共用玻璃底部面板 | 已目视；动态另验 |
| qTeGO | 独立窗口失败转手机屏幕 | A；共用面板、暂停画面与可触及退出 | 已目视；动态另验 |

### 文件与传输：19 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| MaHXL | 文件管理 | A/B/C/D/E；底部文件工具为实体白底 | 已目视；动态另验 |
| W6enLf | 传输中心 | B/C/E；手工来源与剩余时间属于任务状态 | 已目视；动态另验 |
| K950NO | 同名冲突 | A/C/E；共用玻璃抽屉 | 已目视；动态另验 |
| wLQoJ | 选择发送 | A/C/E；选中文件归属保持明确 | 已目视；动态另验 |
| aVAri | Download | A/E；目录路径和目的地不可丢失 | 已目视；动态另验 |
| x4cTCx | 重命名文件 | A；与设备名称输入共用表单节奏 | 已目视；动态另验 |
| VZ4BH | 删除所选文件 | A；危险动作单独表达 | 已目视；动态另验 |
| R759qi | 传输详情 | A/E；逐项结果和普通辅助文案区分 | 已目视；动态另验 |
| Y0LpW | 发送到设备 | E 设备卡；目标确认属于实际任务内容 | 已目视；动态另验 |
| ERONu | 原文件准备中 | 深色条为进度，不可误改为按钮；保留字节与固定来源 | 已目视；动态另验 |
| uhuiJ | 原文件准备好可系统保存 | A；系统保存前后状态区分 | 已目视；动态另验 |
| Gfe22 | 系统保存已取消 | A；取消不删除原文件 | 已目视；动态另验 |
| mcRQa | 已保存到系统位置 | R；保留结果、来源与系统确认 | 已目视；动态另验 |
| vSjZS | 保存未开始就失败 | A；保留未写入与可重试状态 | 已目视；动态另验 |
| pSoci | 系统保存结果待核对 | R；禁用动作与先核对保护保持 | 已目视；动态另验 |
| cdQol | 原文件可分享 | A；交接与最终送达结果区别 | 已目视；动态另验 |
| lm0us | 搜索子文件夹 | A/B/F；条件控件密集且多重胶囊 | 已目视；动态另验 |
| jcZXq | 跨目录搜索进行中 | A/B/F；检查进度属于主状态 | 已目视；动态另验 |
| zD1BI | 已停止的部分搜索结果 | A/B/F；旧条件结果与新条件提示不可误删 | 已目视；动态另验 |

### 相册与内容：9 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| RqDYL | 手机相册 | J明确叠字；B/D；标题与正文脱离同一布局流 | 已目视；动态另验 |
| sepTa | 照片预览 | D/E；独立大标题与实体深灰底部工具 | 已目视；动态另验 |
| Wa6hu | 照片多选 | A/B/C/D/E；照片选中标记在明暗媒体上保持可辨，黑色本身不是问题 | 已目视；动态另验 |
| OLDRn | 森林片段 | A；播放器与照片浮动工具采用同一控制规则 | 已目视；动态另验 |
| w4Qqmf | 无法预览视频 | A/E；失败与替代动作保留 | 已目视；动态另验 |
| KFfP4 | 正在检查手机相册 | A；检查进度为主状态 | 已目视；动态另验 |
| x4oRdN | 部分范围可读与稳定分页 | E；分页状态和不可读警告保留 | 已目视；动态另验 |
| s4p7JF | 已停止且已检查范围为空 | A/E；不能推断未检查范围为空 | 已目视；动态另验 |
| UwGyp | 检查范围与未读项目抽屉 | G；抽屉内容结束后大片空白 | 已目视；动态另验 |

### 通知与接续：5 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| a7A57 | 实时通知 | C/E；通知正文属于真实内容 | 已目视；动态另验 |
| mVNnf | 快捷回复 | A/C/E；设计为底部抽屉，实现为整页 | 已目视；动态另验 |
| Q2B7mM | 从通知进入手机·全屏 | R；远端内容保持原应用外观 | 已目视；动态另验 |
| Ib6xa | 这条通知已失效 | A/E；禁止执行旧动作的状态保留 | 已目视；动态另验 |
| NgsYw | 正在核对回复结果 | A；草稿与未知结果保护属于核心内容 | 已目视；动态另验 |

### 来电与通话：4 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| LVKgj | 来电·音频受限 | C/E；真实音频限制保留为状态正文 | 已目视；动态另验 |
| aLUZD | 通话中 | C/E；圆形控制组与音频路由统一 | 已目视；动态另验 |
| a05tWj | 来电·音频可用 | C/E；初始接听/拒接为横向白胶囊 | 已目视；动态另验 |
| oBEk5 | 另一台设备有来电 | E；保留已有通话与新来电的归属 | 已目视；动态另验 |

### 偏好与恢复：10 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| FkCjb | 画质 | A/B；玻璃面板内选中胶囊的体积与同层关系 | 已目视；动态另验 |
| NVEMy | 设备能力 | A/C/E；功能支持状态保持明确 | 已目视；动态另验 |
| w6WUAT | 设置 | B；独立标题节奏；本机数据区与上方分组不一致 | 已目视；动态另验 |
| zLQT5 | 断线重连 | A；共用玻璃面板，最后一帧与暂停明确 | 已目视；动态另验 |
| DtBNP | 后台与连接 | B/C/E；手工开关行绕过共享开关组件 | 已目视；动态另验 |
| XPceX | 画质细项 | A/B集中；大量full圆角选项；与实现不一致 | 已目视；动态另验 |
| mDL3I | 当前活动 | A/E；连接、画面、传输、声音、通话状态分清 | 已目视；动态另验 |
| PLzIA | 外观 | 设计/实现的选择器位置与分组不同 | 已目视；动态另验 |
| Q2ZaRT | 媒体暂存 | A/E；受保护与可回收空间保持清楚 | 已目视；动态另验 |
| dPgTI | 清理后仍有受保护内容 | 源结构仍有主动作填充；复验禁用语义，不能只改颜色 | 已目视；动态另验 |

### 平板与桌面：2 页

| 页面 ID | 页面名称 | 初始发现／检查点 | 状态 |
| --- | --- | --- | --- |
| H0TFx | 平板工作台 | H；独立侧栏、顶栏与工具，缺少同一功能材料 | 已目视；后续材质另验 |
| zLBrM | 桌面工作台 | H；初始没有共享ref实例，多窗口结构整体手写 | 已目视；后续材质另验 |

## 初始关键问题的对象证据（历史定位）

这些对象ID是问题发现时的定位，节点可能已被后续实施删除或替换，不是当前未修复节点清单。后续闭环见“修复与验收记录”；没有单独的修复回执时不凭共享组件变更宣称逐项关闭。

| 问题 | 初始定位与证据 | 初始处理方向 |
| --- | --- | --- |
| 相册标题重叠 | `RqDYL/u9EJh`为绝对标题，覆盖`P8eSgl`顶部的`OO4kG`范围与`SVxSL`日期；截图看到多组文字混叠 | 待修复、截图复验 |
| 范围抽屉留白 | `UwGyp/wMlbW`固定长抽屉；正文和关闭动作结束后仍有大块空白 | 待改自适应、短内容和长内容复验 |
| 照片工具实体块 | `sepTa/wogV4`初始填充surface且无background_blur，形成大块深灰 | 待采用统一媒体控制材料并复验对比 |
| 搜索装饰渐变 | `E0Ctfk/F6TUTI`为琥珀径向渐变＋blur，引用于`lm0us/jcZXq/zD1BI` | 待删除装饰、检查三页 |
| 主动作与选中形态 | `QXIw5/Ffm0s`的黑白方向按用户要求保留；初始问题应聚焦体积、密度与不统一 | 待核对主题恢复、点缀色、共享组件和覆盖实例；不能因黑色而判失败 |
| 标题体系 | 初始共享标题、旧手写标题、照片标题、设置标题有四套不同节奏 | 待去副描述后统一；检查大字与键盘 |
| 工作台裁剪 | `nqQEb/pf867/uESR9`为完整滚动内容超出视口 | 不是静态损坏；待确认滚动可达、末项不被底部遮挡 |

## 二级描述清理的初始手工特例

以下保留删除／迁移前的定位。共享页头`jRKTF`与共享行`r3Anl`之外的手工副描述已列入逐页实施范围；表内ID不表示当前仍存在。状态、文件元数据与核对内容继续保留。

| 页面 | 手工二级描述对象 |
| --- | --- |
| tbWkA | Jj1jT |
| iEvoR | f8160k |
| MaHXL | UPKIg |
| W6enLf | JqMGC |
| K950NO | l5Vqvz |
| a7A57 | MHeZc |
| mVNnf | vJylf |
| LVKgj | EUb6v |
| aLUZD | nFMRp |
| NVEMy | CQc8A |
| wLQoJ | q1Xizp |
| DtBNP | Vu7m5 |
| Wa6hu | qgfGT |
| a05tWj | kMzZM |
| tch6A | ofM0S |
| sepTa | jhtlu内im5CT，独立来源保护层 |

其他手工或独立母组件：

| 对象 | 初始内容／处理注意 |
| --- | --- |
| nqQEb/D2aCoO | Hero“真实画面、原有应用与登录状态” |
| DtBNP/hcpjo、vhAdT | 两条手工开关描述 |
| sepTa/oXBhp | 底部工具的原文件大小与来源辅助行 |
| D11Zj/T1NnAJ | 开关母组件描述 |
| RTx0Z/iZ4ld | 设备卡第二层辅助信息 |
| RTx0Z/Go5Bw | 设备当前状态；精简位置时保留状态语义 |
| H0TFx/TFMKf、zLBrM/Tnq4a | 大屏侧栏连接和电量辅助行 |
| H0TFx/hF0wn | 通知条“在手机中打开并继续会话” |
| x5m8En/zLCqC | 流程反馈描述，按实际状态正文判断 |
| iEvoR/O7BHy | 手工会话摘要 |
| H0TFx/L7NGQ、zLBrM/Nj3ES | 大屏顶栏标题组，需继续检查其手工状态子项 |

提示：移除文字后同步修改父布局间距、最小高度、固定高度与空容器；不要以enabled=false后仍占位的结构制造空洞。原应用内正文、通知内容、文件元数据与任务结果不可因字体角色相同而被误删。

## 41 个实现页对应关系

下表同时列当前设计覆盖、源码处理和最新夹具截图。初始7个缺稿独立代表页已补齐；系统自身文件选择器和分享面板不另造产品页。每页浅／深色截图均已捕获，但不能据此关闭各页所有异常、系统交接或真实设备业务状态。

| 实现文件（相对lib/pages） | 当前设计对应ID | 当前实现／回归依据 | 最新夹具截图 |
| --- | --- | --- | --- |
| activities/activities_page.dart | mDL3I | 设备名与活动名同行，停止操作保留设备归属；中性分组，无二级说明。 | [浅](/tmp/connect-ios-review/activities-light.png)／[深](/tmp/connect-ios-review/activities-dark.png) |
| add_device/add_device_page.dart | W3GRn | 连接方式统一分组，移除ActionRow外重复Divider；授权步骤作为正文保留。 | [浅](/tmp/connect-ios-review/add_device-light.png)／[深](/tmp/connect-ios-review/add_device-dark.png) |
| appearance/appearance_page.dart | PLzIA | 三项外观分组，选中末尾check，取消左侧radio。 | [浅](/tmp/connect-ios-review/appearance-light.png)／[深](/tmp/connect-ios-review/appearance-dark.png) |
| apps/apps_page.dart | tbWkA、tch6A、Nph5q | 系统搜索、惰性分组应用行、共享任务选择sheet；去除包名副标题。 | [浅](/tmp/connect-ios-review/apps-light.png)／[深](/tmp/connect-ios-review/apps-dark.png) |
| background/background_page.dart | DtBNP | 全部开关改Cupertino，设置分组；实际后台资格与错误仍作为内容。 | [浅](/tmp/connect-ios-review/background-light.png)／[深](/tmp/connect-ios-review/background-dark.png) |
| calls/calls_page.dart | LVKgj、aLUZD、a05tWj、oBEk5 | 来电协议状态本地化；拒接浅危险背景、亮红图标与可读文字，浅深色文字对比均达4.5。 | [浅](/tmp/connect-ios-review/calls-light.png)／[深](/tmp/connect-ios-review/calls-dark.png) |
| capabilities/capabilities_page.dart | NVEMy | 中性内容面展示真实支持状态；限制原因作为内容保留，无设备副标题。 | [浅](/tmp/connect-ios-review/capabilities-light.png)／[深](/tmp/connect-ios-review/capabilities-dark.png) |
| connection_form/connection_form_page.dart | XQZRD、YvzMk、E0CAl、gOwYI、pFGBZ、OpFKk | 紧凑输入、选择和按钮；配对/TLS/旧TCP逻辑及就地授权说明保留。 空值／错误提交由同一Form.validate就地解释且0协议请求；不再使用完整后才启用按钮的旧契约。 | [浅](/tmp/connect-ios-review/connection_form-light.png)／[深](/tmp/connect-ios-review/connection_form-dark.png) |
| data_preferences/data_preferences_page.dart | XABsw | 记录导入导出分组，无副标题；授权身份说明及确认保留。 | [浅](/tmp/connect-ios-review/data_preferences-light.png)／[深](/tmp/connect-ios-review/data_preferences-dark.png) |
| device_connection_preferences/device_connection_preferences_page.dart | q3bM72 | 连接偏好统一分组；编辑地址和USB入口行为保留。 | [浅](/tmp/connect-ios-review/device_connection_preferences-light.png)／[深](/tmp/connect-ios-review/device_connection_preferences-dark.png) |
| device_details/device_details_page.dart | TMxVJ、eDTbS、Txxv0、I6WG6Q、zyRl5 | 实际信息/设备状态保留；设备开关Cupertino，管理行统一分组。 | [浅](/tmp/connect-ios-review/device_details-light.png)／[深](/tmp/connect-ios-review/device_details-dark.png) |
| device_workspace/device_workspace_page.dart | nqQEb | 紧凑设备标题、黑白主动作；功能图标蓝/橙/红/绿分工，普通功能统一分组。 | [浅](/tmp/connect-ios-review/device_workspace-light.png)／[深](/tmp/connect-ios-review/device_workspace-dark.png) |
| devices/devices_page.dart | lUDPa、tSC6u、OxyeM、W7Lua、HvaW2、oHSUW、lj24R | 根标题17；280宽2×状态保持单行、名称占剩余宽度；短横屏标题搜索同行，首设备完整可见。 | [浅](/tmp/connect-ios-review/devices-light.png)／[深](/tmp/connect-ios-review/devices-dark.png) |
| diagnostics/diagnostics_page.dart | eWu3m | 检查项统一分组；非正常检查的实际恢复原因作为独立错误内容保留，无通用副标题。 | [浅](/tmp/connect-ios-review/diagnostics-light.png)／[深](/tmp/connect-ios-review/diagnostics-dark.png) |
| discovery/discovery_page.dart | yMlVd、h5JZfa | 设备列表分组；授权事实说明和连接路由行为保留。 | [浅](/tmp/connect-ios-review/discovery-light.png)／[深](/tmp/connect-ios-review/discovery-dark.png) |
| document_export/document_export_page.dart | HwqEs；与uhuiJ等链路相关 | 原文件名称/小图标与实际保存/冲突表单；取消通用副标题。 | [浅](/tmp/connect-ios-review/document_export-light.png)／[深](/tmp/connect-ios-review/document_export-dark.png) |
| document_import/document_import_page.dart | MIxzU | 共享输入/按钮/圆形勾选；图标Align固定40方形，来源检查和部分确认保留。 | [浅](/tmp/connect-ios-review/document_import-light.png)／[深](/tmp/connect-ios-review/document_import-dark.png) |
| file_details/file_details_page.dart | Z5rvv | 取消大图标及重复文件名；大小和完整路径为实际详情，取回/分享保留。 | [浅](/tmp/connect-ios-review/file_details-light.png)／[深](/tmp/connect-ios-review/file_details-dark.png) |
| file_search/file_search_page.dart | lm0us、jcZXq、zD1BI | 惰性分组搜索；同名文件完整路径Tooltip可区分，无法操作的原因作为实际错误正文。 | [浅](/tmp/connect-ios-review/file_search-light.png)／[深](/tmp/connect-ios-review/file_search-dark.png) |
| files/files_page.dart | MaHXL、aVAri、x4cTCx、VZ4BH、wLQoJ | glass图标组、惰性分组文件行；路径鼠标hover可见且不抢占长按选择，非法名原因保留。 | [浅](/tmp/connect-ios-review/files-light.png)／[深](/tmp/connect-ios-review/files-dark.png) |
| gallery/gallery_page.dart | RqDYL、Wa6hu、KFfP4、x4oRdN、s4p7JF、UwGyp | 紧凑标题/glass工具与统一网格圆角；范围sheet/选取保留，夹具总数1/1一致。 | [浅](/tmp/connect-ios-review/gallery-light.png)／[深](/tmp/connect-ios-review/gallery-dark.png) |
| home/home_page.dart | Ffm0s（共享导航）；H0TFx、zLBrM（响应布局） | 手机浮动tab、宽屏侧栏＋当前单页；两大屏稿已收敛到此结构，不宣称桌面原生并行窗口。 | [浅](/tmp/connect-ios-review/home-light.png)／[深](/tmp/connect-ios-review/home-dark.png) |
| incoming_share/incoming_share_page.dart | Y0LpW | Cupertino内容开关、设备末尾check；取消/关闭文字动作独立于玻璃图标组，真实正文保留。 | [浅](/tmp/connect-ios-review/incoming_share-light.png)／[深](/tmp/connect-ios-review/incoming_share-dark.png) |
| media_cache/media_cache_page.dart | Q2ZaRT、dPgTI | 实际占用/可回收量与保护状态保留；中性分组，清理行为保持。 | [浅](/tmp/connect-ios-review/media_cache-light.png)／[深](/tmp/connect-ios-review/media_cache-dark.png) |
| media_preview/media_preview_page.dart | sepTa、OLDRn、w4Qqmf | 全屏内容与clear返回/保存分享；文件名为普通单行文字，导航后局部渐退scrim保护可读性。 | [浅](/tmp/connect-ios-review/media_preview-light.png)／[深](/tmp/connect-ios-review/media_preview-dark.png) |
| notification_reply/notification_reply_page.dart | mVNnf、NgsYw | 整页紧凑标题，真实通知正文保留；系统输入/动作，无应用/设备副标题。 | [浅](/tmp/connect-ios-review/notification_reply-light.png)／[深](/tmp/connect-ios-review/notification_reply-dark.png) |
| notifications/notifications_page.dart | a7A57、Ib6xa | 真实通知正文及动作保留，无页级副标题；菜单/按钮沿用共享规范。 | [浅](/tmp/connect-ios-review/notifications-light.png)／[深](/tmp/connect-ios-review/notifications-dark.png) |
| qr_pair/qr_pair_page.dart | G4CpTk | QR尺寸用生成token；授权步骤保留，紧凑标题/共享按钮。 | [浅](/tmp/connect-ios-review/qr_pair-light.png)／[深](/tmp/connect-ios-review/qr_pair-dark.png) |
| quality/quality_page.dart | FkCjb、XPceX | 分组预设末尾check；当前尺寸px、帧率fps、码率Mbps有明确单位，限制原因保留。 | [浅](/tmp/connect-ios-review/quality-light.png)／[深](/tmp/connect-ios-review/quality-dark.png) |
| receive_content/receive_content_page.dart | ERONu、uhuiJ、Gfe22、mcRQa、vSjZS、pSoci、cdQol | 真实文件、进度、冲突和保存动作保留；来源→目标同行显示必要归属，取消通用副标题。 | [浅](/tmp/connect-ios-review/receive_content-light.png)／[深](/tmp/connect-ios-review/receive_content-dark.png) |
| remote/remote_page.dart | aVxBi、DtZbX、D5Cjet、D3HWzx、P8F1YG、HjBtR、qTeGO、Q2B7mM、zLQT5、FkCjb | 全屏/三键/Back/关闭/越界行为保持；任意远控内容的退出控件使用regular，异常可滚动。 | [浅](/tmp/connect-ios-review/remote-light.png)／[深](/tmp/connect-ios-review/remote-dark.png) |
| route_error/route_error_page.dart | MJ3me | EmptyContent使用统一字级/按钮，紧凑glass返回，恢复操作保留。 | [浅](/tmp/connect-ios-review/route_error-light.png)／[深](/tmp/connect-ios-review/route_error-dark.png) |
| session_tools/session_tools_page.dart | XvviW | 会话选择及工具统一分组与点缀；截图/键盘/导航意图路由保持。 | [浅](/tmp/connect-ios-review/session_tools-light.png)／[深](/tmp/connect-ios-review/session_tools-dark.png) |
| sessions/sessions_page.dart | iEvoR | 会话running按领域显示运行中，名称与状态同行；工具/暂停/关闭保留，无副标题。 | [浅](/tmp/connect-ios-review/sessions-light.png)／[深](/tmp/connect-ios-review/sessions-dark.png) |
| settings/settings_page.dart | w6WUAT | 56高根标题17，全部设置统一分组；去营销描述及行副标题。 | [浅](/tmp/connect-ios-review/settings-light.png)／[深](/tmp/connect-ios-review/settings-dark.png) |
| share_directory_picker/share_directory_picker_page.dart | FeFSp | 分组目录选择与共享按钮，实际路径及选择行为保留。 | [浅](/tmp/connect-ios-review/share_directory_picker-light.png)／[深](/tmp/connect-ios-review/share_directory_picker-dark.png) |
| startup_error/startup_error_page.dart | s9FWkN | 失败正文可滚动，去除用户无关Bad state/Exception前缀，保留具体原因与重试。 | [浅](/tmp/connect-ios-review/startup_error-light.png)／[深](/tmp/connect-ios-review/startup_error-dark.png) |
| transfer_details/transfer_details_page.dart | R759qi、K950NO | 真实名称/状态/来源目标/逐项结果保留，结果状态同行，冲突表单统一。 | [浅](/tmp/connect-ios-review/transfer_details-light.png)／[深](/tmp/connect-ios-review/transfer_details-dark.png) |
| transfers/transfers_page.dart | W6enLf | 56高根标题17/glass刷新，中性任务面/亮橙点色；实际进度和来源目标保留。 | [浅](/tmp/connect-ios-review/transfers-light.png)／[深](/tmp/connect-ios-review/transfers-dark.png) |
| usb_guide/usb_guide_page.dart | OxUaB、WMggr、ONn92、w38WDx、vPWPs | 亮橙USB的40方形图标不再受列表拉伸；两端授权步骤保留。 | [浅](/tmp/connect-ios-review/usb_guide-light.png)／[深](/tmp/connect-ios-review/usb_guide-dark.png) |
| wireless_guide/wireless_guide_page.dart | c0wxY、HevUb、xq5If部分相关 | 蓝色无线40方形图标不再受列表拉伸；真实步骤与配对、扫码、旧TCP入口保持。 | [浅](/tmp/connect-ios-review/wireless_guide-light.png)／[深](/tmp/connect-ios-review/wireless_guide-dark.png) |
当前公共实现已统一：PageFrame使用单行语义标题与共享玻璃返回／图标组，真实文字动作通过`trailingAction`独立；ChoiceRow采用末尾勾选；Home选中态使用浅中性选择层，主题primary保持黑白。文件名为普通文本，任意远控内容的退出控件改regular，媒体控制保留clear。上述源码及定向回归已核对；真实折射效果仍待GPU记录。

原92手机页实际截图批次如下。第一批为材质代理回执，第二批为页面审计代理逐页TakeScreenshot；两批互不重叠，排除新增7页、2大屏与组件板／分组标题。

- 第一批46页：`lUDPa tSC6u HvaW2 oHSUW lj24R OxyeM W7Lua nqQEb TMxVJ eDTbS q3bM72 eWu3m I6WG6Q Txxv0 zyRl5 W3GRn yMlVd h5JZfa c0wxY XQZRD YvzMk E0CAl G4CpTk gOwYI pFGBZ xq5If HevUb OpFKk OxUaB WMggr ONn92 w38WDx vPWPs DtZbX D5Cjet D3HWzx P8F1YG tbWkA Nph5q aVxBi iEvoR HjBtR XvviW tch6A qTeGO MaHXL`。
- 第二批46页（按本文分组列出）：`W6enLf K950NO wLQoJ aVAri x4cTCx VZ4BH R759qi Y0LpW ERONu uhuiJ Gfe22 mcRQa vSjZS pSoci cdQol lm0us jcZXq zD1BI RqDYL sepTa Wa6hu OLDRn w4Qqmf KFfP4 x4oRdN s4p7JF UwGyp a7A57 mVNnf Q2B7mM Ib6xa NgsYw LVKgj aLUZD a05tWj oBEk5 FkCjb NVEMy w6WUAT zLQT5 DtBNP XPceX mDL3I PLzIA Q2ZaRT dPgTI`。
- 新增7页：`XABsw FeFSp Z5rvv MIxzU MJ3me s9FWkN HwqEs`；大屏2页：`H0TFx zLBrM`。

## 统一规则与衍生验证

所有视觉值继续来源于 [design.md](../../designs/design.md) 和对应 Pencil implementation token，不在此文另建规范。

- 保留黑白主题和黑色主要动作；中性分组内容承载文件、通知、表单与设备信息。亮色仅用于语义明确的图标和状态点缀，不能将整个主题改蓝；正文不要用亮色降低可读性。
- 玻璃用于浮动导航、工具、菜单与sheet；不要给每个普通列表行加玻璃，也不要多层完整玻璃互叠。
- 标题与普通列表项删去二级描述后，统一单行导航语义和行节奏；实际状态与任务正文保留。
- 远端Android界面、照片和视频保持原内容外观；主控主题色与点缀色不污染远端内容。
- 降低透明度采用清晰实体材料；减少动态保留即时反馈；辅助变体不能因“更像玻璃”被覆盖。

## 修复与验收记录

| 范围／初始问题 | 当前处理与证据 | 结果与限制 |
| --- | --- | --- |
| 逐页覆盖与7缺稿 | 原92手机各46页实际截图；新增7页逐张截图、Get实例检查；2大屏截图回执；上表41源码页均有浅深截图 | 101页静态查看与7代表稿覆盖完成；不等于101个业务状态运行通过 |
| 黑白主题、点缀、紧凑分组 | 共享规范与生产组件保留primary；功能图标语义色；普通内容分组、导航浅选中；描述型副标题删除 | 源码、Pencil逐页与Widget截图证据；最终GPU对比仍单列 |
| 初始假入口／结构不一致 | `aVxBi`去旧边框、`iEvoR`去旧会话摘要、`q3bM72`收敛3个真实入口、`MaHXL`补路径并去假分类、`lj24R`去假添加入口、`nqQEb`改真实分组列表；材质代理收到Get或局部重拍回执 | 初始项已有后续处理，不能继续全部标为待修复；真实业务分支另测 |
| 误用玻璃 | 媒体静态文件名改普通文字；PageFrame文字动作独立；远控退出改regular；内容面维持实体 | `ios_review_regressions`、`exit_handle`等定向回归；不是原生Liquid Glass等效认证 |
| 对齐、分隔、方形图标、状态与单位 | 页头左右对齐；删除重复Divider；引导／导入图标不拉伸；来电/会话状态本地化、画质值带单位、启动错误去异常前缀；拒接文字浅深对比达测试门槛 | 9文件33项定向通过，详见日志；文字实际可读仍有物理屏幕边界 |
| Flexible与内容可达 | 全页父约束280×620、620×280及2倍文字；根导航窄pane／宽短pane；短横屏首个设备完整露出；媒体画布填满父约束 | 布局回归通过；不外推为所有键盘、任意长数据及TalkBack均通过 |
| 当前96图 | 41页×2＋5额外状态×2＋4根导航响应截图；捕获等待图片首帧，修复旧暗媒体空图 | 当前96张已生成，最新媒体由页面代理打开复验；此前材质代理的全96逐张查看属于上一捕获版本 |
| 表单校验契约 | 主代理已决定空／非法字段允许点击提交，Form.validate原位解释，0协议请求；`E0CAl/KOnCl`已同步可点击连接、红色端口错误保留 | 该行为有定向用例；旧“完整后才启用”表述已由规范代理同步，不列为开放产品问题 |
| 快捷回复与画质的旧稿差异 | 主代理确认`mVNnf`已改整页通知＋输入／发送；`XPceX`为3预设choice＋5细项内容行，与源码下钻一致；远控内`FkCjb/h7lWL`继续使用sheet | 初始sheet／chips与整页脱节已有针对性收敛；保留页内画质和远控上下文画质两种真实入口，不把二者误判为同一布局 |
| 大屏结构 | `H0TFx`侧栏＋设备列表，`zLBrM`侧栏＋单设备工作台，材质代理2页截图与22直接ref检查 | 当前稿不再要求假并行工作区；后续共享材质更新及其他宿主运行仍需复验 |
| 最终全量与生成 | 根应用全量323个非hidden项成功；后续2处纯lint修复后3文件13项成功并重拍96图；analyze无问题；generate.py --check含FRB／build_runner成功；design_system 11、Node 4回归通过 | 已有各自日志与代理回执；不把历史Rust301／桥接131重复记成本轮重新运行 |
| 动态GPU采集与有限目视 | Android实际9图；shader支持／加载、交互、场景像素标记及host校验均true，Lite=false；材质代理逐张实际查看；降低透明度3图光学组件全0 | 采集契约与有限静态画面复核完成；工具`visualAcceptanceComplete=false`保留，不能扩大为原生等效／完整动态形变／性能通过 |
| 真实Android产品r2 | H.265实际486×1080编码／解码，默认三键、Back保留远控、letterbox点击静默、退出把手内向展开、关闭仅暂停本地呈现与退出后停止设备声音全部true | productAcceptanceComplete=true，root已查看Back／letterbox后远控与工作台截图；不外推至其他物理设备或四宿主 |

最终运行记录：

- [根应用全量](/tmp/connect-final-tests.jsonl)：`flutter test --no-pub --reporter json`，323个非hidden项全部success，最终done.success=true。随后只修startupError无用插值和测试braces两处lint；[三文件回归](/tmp/connect-final-pages.jsonl)13项全部success，包含`ios_review_regressions`、`ios_pages_layout`与96图重新捕获。
- [Flutter analyze](/tmp/connect-final-analyze.log)：No issues found；[生成一致性](/tmp/connect-final-generate.log)：官方DESIGN.md lint 0错误63警告，FRB Rust／Dart与build_runner输出检查成功；材质代理design_system 11测试、Node生成器4测试通过。
- [真实产品r2回执](/tmp/connect-final-product/result.json)、[drive日志](/tmp/connect-final-product-r2.log)：productAcceptanceComplete及上表真实流程项全部true。首次r1因画质UI新增px单位而旧测试仍查裸数字失败；修正为精确px期望后r2通过，没有改产品行为或放宽画质门槛。

GPU回执：[result.json](/tmp/connect-glass-material/result.json)，9图位于`/tmp/connect-glass-material`。`shaderImageFiltersSupported`、`shaderProgramsLoaded`、`functionalAcceptanceComplete`、`opticalCaptureComplete`、`sceneMarkerPixelValidationComplete`与`hostValidationComplete`为true。材质代理已实际逐张查看marker 42241–42249的9图：clear明暗图左上close内蓝条在边缘弯折／位移并透入背景；regular浅深与滚动图文字清楚，未见额外异常黑块、斜线或截断；reduced三图为实色、不透背景，与Lens=0一致。规则黑方块与中央marker是测试背景，不当成材质缺陷。pressed含debug指针与Tooltip，只证明按压状态被捕获，不能据此验收细微形变、动态高光、释放回弹或性能。

工具报告仍保持`visualReviewRequired=true`、`visualAcceptanceComplete=false`：自动化harness不签发人工质量认证，**这不抹去上述另行完成的有限9图人工复核，也不表示该复核失败**。未改写工具生成结果，未将有限目视扩大为Apple原生等效。

最终普通`lib/main.dart`Android-x64 debug APK已构建并通过ZIP／x64 ELF／apksigner检查，[产物回执](/tmp/connect-final-main-apk.json)记录147,239,422字节、SHA256 `b7c766abfc6a94a2166af30fa2a4572898deb297e4a6ae62c94b5973e91073e8`；唯一保留`build/app/outputs/flutter-apk/app-debug.apk`。覆盖安装启动观察到Impeller OpenGLES且未见UnhandledException，普通入口启动不等同重复完整业务。[清理回执](/tmp/connect-final-cleanup.json)删除23项、2,087,737,945字节（约1.944GiB），保留验收证据与共享Rust／native缓存；目标5556及临时15556转发已移除，保留原主控5554。

仍需保留的验证边界：多路真实视频Texture在玻璃后移动、完整按压形变与取消恢复过程、背景适应阴影／对比、原生级形变与可打断来源过渡、物理设备系统返回手势、读屏、减少动态、高对比、真实系统选择与分享交接、未知保存结果核对、部分读取未确认时的保护，以及多设备音频听测／剪贴板权限。现有单测、夹具和静态设计各自覆盖已列范围，不代替这些证据。

## 新增7页登记与静态检查（2026-10-19）

本节是初始审计后的补稿记录。上述94页清单保留初始问题，原“缺稿01–07”已经关闭独立代表稿缺失项；对应独立代表页现已补入同一Pencil源稿，当前为 **101页：99手机页、2大屏页**。新增画布分组为 `NC0PD`“补全页面”，通过 FindEmptySpace 放在既有组下方，7页均为独立root Frame。

| 原缺稿项 | 新增Frame ID | 页面 | 对应实现 | 本次代表态 |
| --- | --- | --- | --- | --- |
| 缺稿01 | XABsw | 设备记录与恢复 | data_preferences/data_preferences_page.dart | 授权身份边界、导出与恢复记录入口 |
| 缺稿02 | HwqEs | 保存到系统位置 | document_export/document_export_page.dart | 原文件已就绪、用户尚未调用系统位置选择 |
| 缺稿03 | MIxzU | 发送本机文件夹 | document_import/document_import_page.dart | 部分内容已取回、显示跳过项目和固定目标、用户已勾选核对 |
| 缺稿04 | Z5rvv | 文件详情 | file_details/file_details_page.dart | 文件名称、大小、实际路径、取回与系统分享 |
| 缺稿05 | MJ3me | 路由内容不可用 | route_error/route_error_page.dart | 可重试的内容读取失败、返回设备列表 |
| 缺稿06 | FeFSp | 选择目标目录 | share_directory_picker/share_directory_picker_page.dart | 当前目录、上一级、目录列表与使用当前目录 |
| 缺稿07 | s9FWkN | 启动失败 | startup_error/startup_error_page.dart | 启动服务失败与重新启动；按实际实现保持居中且不添加虚构返回入口 |

新增页沿用当前 `wbM5x` 单行页头、`OuAnF` 单行内容行、`QXIw5` 主动作、`anf55` 次动作、系统状态/手势组件与圆形控制refs；没有创建新的母组件或变量。启动失败实现没有AppBar，因此该页保留实现中的无页头布局。没有新增产品开关或无意义控制来强行使用 `D11Zj`。黑白主题与黑色主动作保留，蓝/橙/红仅用于功能图标与真实受限状态点缀；普通内容区域保持实体中性材料。

**本次真实完成的静态验证：**

- 新增7页均使用手机参考视口与纵向Flex内容布局；目录页的确认动作位于内容末端，正文与底部安全区分开。
- 通过 TakeScreenshot 实际查看全部7个新增页。首次截图暴露了视口与部分图标尺寸未解析的问题，已在新增对象内修正，并重截受影响页；最终截图中图标、标题、正文和动作可见，没有重叠、裁切或遮挡。该次补稿检查本身不覆盖旧94页；旧页后来分两批完成截图查看，见前文。
- 对新增7页逐页执行 Get 可见实例布局检查：未报告 partially/fully clipped；检查变量引用无缺失，页面边界与所有其他root无相交。新增页合计36个直接组件ref，引用均为既有共享组件；没有编辑既有94页、母组件或变量。
- 七页为当前代表态的静态设计。文件夹、文件名称、计数、错误文案为示例数据，不是实际文件操作或真机故障结果；没有执行导入、保存、分享、恢复记录或服务重启。

**后续状态：**新增7个实现页面已纳入当前96张浅／深色Widget截图。仍待真实业务验证：部分读取未勾选时禁用主动作、零内容/取消/失败、系统保存结果未知、长路径和长文件名、大文字/窄屏、错误重试、读屏及真实系统文件选择交接。补稿完成只关闭“缺少独立代表页”这一项，不关闭这些衍生状态和业务验收。

