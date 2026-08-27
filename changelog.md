# 更新记录（Changelog）

本文件记录每次合入 `develop` 的变更。项目尚无版本号发布，按日期归档；后续如进入版本发布节奏，可将「未发布」区整体归档为 `[版本号] - 日期`。

## 维护约定（必读）

- **每次更新**（PR 合入或直推 `develop`）必须在「未发布」区追加条目，注明任务/PR 编号。
- CI（`changelog-check`）会校验每次 PR 与直推是否修改了本文件；确属不影响行为的改动（如纯格式化、CI 自身修复），可给 PR 打 `skip-changelog` 标签豁免。
- 条目按 `新增 / 变更 / 修复 / 文档 / 工程` 分类，一句话说清「改了什么 + 为什么」，并附任务键（WORD-NN）与 PR 编号。

## [未发布]

### 变更

- UI 全面换装扁平卡通风（仓库基地视觉升级 M2）：PixelUiKit 内部从「低分辨率 Image → 最近邻放大 → StyleBoxTexture」整体替换为原生 StyleBoxFlat（圆角面板 + 钢蓝描边 + 柔和落影），调色板对齐仓库概念图（奶油白面板/钢蓝框/警示黄/主行动红/青绿），方法签名与类名不变（调用方零改动）；HUD 图标（货币/生命/氧气/仓库/背包/沙漏）改为 96×96 高分程序化卡通绘制；全仓清除控件级 TEXTURE_FILTER_NEAREST（场景图标节点同步改 LINEAR，等距基地贴图保留至 M3 替换）（feat/warehouse-base-v1）
- 抽取统一弹窗骨架 PopupBase（Dim + 居中凸台面板 + 内容区，可选标题/内建关闭钮）：首页仓库出售弹窗与局内搜索弹窗两处手搓同构结构迁移完毕，对应 tscn 子树删除改为程序化构建（feat/warehouse-base-v1）
- 装载页/结算页接入 PixelUiKit 还清视觉债：确认/取消/选择/结算按钮统一圆角凸台样式（feat/warehouse-base-v1）
- 对局地图容器区内衬、主页生命/氧气条内衬由深色系改浅色主题配色；主页顶条文字（货币/角标）改暗底亮字保证可读性（feat/warehouse-base-v1）

### 变更（续）

- 渲染器迁移 gl_compatibility（仓库基地视觉升级 M1）：锁定 Web 小游戏方向（Godot 出 Web 仅支持 Compatibility），纯 2D 项目无 Mobile 依赖；project.godot 移除 d3d12 驱动指定，config/features 同步更新；场景资产自此按原生平滑卡通基准使用 LINEAR 过滤（现存像素 NEAREST 节点由后续里程碑统一清理）（feat/warehouse-base-v1）
- 内嵌中文 OFL 字体 NotoSansSC-Regular 并设为全局默认主题字体（gui/theme/custom_font）：Web 导出无系统字体回退，中文字形必须自带；附 OFL 许可文件（feat/warehouse-base-v1）
- lobby_preview 工具补拍入场帧：新增 stage0 大厅页截图（lobby_preview_home.png），此前仅覆盖对局后阶段，渲染器迁移回归缺少大厅对照（feat/warehouse-base-v1）
- WORD-40 局内页面重构（首页同款像素风）：顶部 HUD 改为三属性图标条——本局时间（沙漏+倒计时）/撤离目标（木箱+容器 x/N）/携带数（背包+件数）；撤离读条（金色进度条+剩余秒数）移至地图区底部显示；操作区改三枚圆形像素钮（搜索/撤离/完成，超时调试钮转为隐藏钩子，测试契约节点名不变）；底部新增背包+安全箱格阵（6+1 列×4 行），携带物品按品质色填入背包格；新增搜索弹窗——容器内部空间可视化（如 3x3/4x4 格），逐格扫描动画+品质色揭晓（纯表现层回放，领域侧逻辑不变），地图容器实体沿用可点击按钮契约（`%MapContainers`，完成态「已搜索」标记）（feat/lobby-home-ui）
- WORD-40 像素 UI 管线共享化：调色板/品质色/按钮与格子样式助手提升至 PixelUiKit 单一来源（epic 品质色对齐示意草图为红色系），首页与局内共用；按钮补充禁用态样式；编排器新增 backpack_item_ids() 只读访问器（局内背包格按放置顺序渲染物品品质）（feat/lobby-home-ui）
- 合并 bugfix/loadout-container-timer：入场货币校验/地图容器实体/双计时停滞修复（详见该分支条目）（feat/lobby-home-ui）

### 新增

- Web 导出 preset（export_presets.cfg，导出路径 build/web/，排除 assets/art/source_raw 原图目录）；本机尚未安装 Godot 导出模板，真实导出冒烟待模板安装后执行（feat/warehouse-base-v1）

### 工程

- 收编未跟踪的 tests/integration/test_map_containers.gd.uid（Godot 4 uid 文件缺失会丢导入元数据）；.gitignore 排除 AI 生图原图目录 assets/art/source_raw/ 与本地导出产物 build/（feat/warehouse-base-v1）

### 修复

- 主线验证问题 1（AC-02/AC-21 入场货币校验）：移除「档案已持有档位跳过购买」路径——0 货币仍可携高价背包免检入场；入场购买改为每局一次（事务引用按 runId 唯一，跨局各自扣款、同局重复确认被 LOADOUT 阶段守卫拦截），余额不足留在装载页并提示所需价格
- 主线验证问题 2（AC-17 核心搜刮图形化）：对局地图新增按本局计划生成的可点击容器实体（数量读 GameConfig.match_container_count，容器类型读配置数据；点击即搜索该容器并携带产出，已完成容器禁用标记不重复搜索）；修复入场后局内按钮停留在禁用态的问题（RUN_INIT -> IN_RUN_LOCKED 无事件，改为表现层每帧轮询阶段变化刷新）；搜索产出实例 id 加 runId 前缀（修复第二局同容器携带被实例幂等静默拒绝）
- 主线验证问题 3（AC-10/AC-11 双计时）：RunSessionService/ExtractService 的 tick 用 int(delta) 截断帧级浮点增量（每帧 ~0.016s 全部丢失）导致总时间与撤离读条停滞——改为浮点累积满整秒再扣减，余量随局/每次撤离开始复位（INV-14）；HUD 撤离读条总量改读配置（不再硬编码 15 秒）
- 伴随测试修正：test_container_search_wiring 多局复位用例改走合法撤离流程（旧用例依赖无阶段守卫的确认入场）；test_telemetry_wiring 出售价值解析改经物品定义（解耦编排器内部实例 id 命名）

### 测试

- 新增回归用例：0 货币已持有档位入场拦截、每局重复扣款、双确认防护（test_profile_loadout_wiring）；帧级浮点计时累积与余量复位（test_run_session_service/test_extract_service）；本局容器计划与按容器搜索幂等（test_container_search_wiring/test_telemetry_wiring）；地图容器实体 GUI 可点击（tests/integration/test_map_containers.gd，全局 EventBus 进程级单例下一局一套件）

### 新增

- WORD-40 程序化像素画具 PixelArtKit 与首页基地视图 BaseView：低分辨率画布 + 整数倍最近邻放大实现像素化 2.5D，主屋/仓库棚/菜园/水塔/旗杆等元素与旗帜/信标轻量动画，纯表现无业务（feat/lobby-home-ui）
- WORD-40 开发辅助工具 tools/lobby_preview.gd：窗口模式黑盒驱动页面流程并分阶段截图到 reports/（现覆盖「入场 -> 对局 -> 搜索弹窗 -> 撤离读条」），便于 UI 迭代自查（feat/lobby-home-ui）

## [2026-08-26]

### 新增

- 切片3 Profile+Loadout：购买/选择/扣款走 Transaction 域原子性 + 初始货币档案 + 接线测试（WORD-33，PR #8）
- 切片4 RunSession：每局实例、双计时、完成数、settled（WORD-34，PR #12）
- 切片5 Item & Inventory：数据驱动物品定义 + 背包/安全箱格子 + 放置校验（WORD-35，PR #12）
- 切片6 Loot/Container：容器搜索子状态机 + 逐件揭晓幂等 + 完成计数（WORD-36，PR #12）
- 切片7 Extract：撤离锁定/解锁 + 15 秒并行计时 + 顶层状态机接线（WORD-37，PR #12）
- 切片8 Settlement+Warehouse+Transaction：成败结算/入库/出售/货币，Transaction 域保证扣款/入账原子性（WORD-38，PR #12）
- 切片9 Telemetry+表现层接场景/UI：遥测埋点 + 局内/局外界面接线 + 强制功能链闭环验证记录（WORD-39，PR #12）

### 文档

- 补录《FullHaul 产品项目规范 V0.1-baseline-02》docx（批准基线，2026-08-21）

### 工程

- 补齐 db/仓储接口脚本的 `.uid` 文件（对齐仓库既有 `.uid` 跟踪）
- 新增 `changelog.md` 与 `changelog-check` CI 校验，保证每次更新附带更新记录

## [2026-08-25]

### 新增

- 基础框架-1：工程标准化目录 + 事件总线 + 配置加载（Autoload 基础设施）（WORD-23，PR #1）
- 基础框架-2：领域层接口 + 顶层状态机骨架（域拆分）（WORD-24，PR #2）
- 基础框架-3：GdUnit4 单元测试基建 + 地基测试（WORD-25，PR #3）
- 基础页面 V0：应用编排层 + 表现层事件驱动接线；界面调整为 9:16 竖屏设计（1080×1920，短边 1080）（WORD-26，PR #4）
- 数据库设计与搭建：SQLite 选型 + 建表/迁移脚本 + 领域仓储接口 + 基础设施实现（WORD-30，PR #5→#6 链式合入）
- 数据库接入游戏系统：仓储内存/SQLite 配置切换 + 编排器接线 + 结算存档落库 + 接线测试（WORD-31，PR #7）

### 文档

- 补录《FullHaul 架构设计文档 V0.1》（返工版，源自 agent 会话快照）

## [2026-08-21]

- 初始提交（工程骨架 `a432520`）
