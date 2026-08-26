# 更新记录（Changelog）

本文件记录每次合入 `develop` 的变更。项目尚无版本号发布，按日期归档；后续如进入版本发布节奏，可将「未发布」区整体归档为 `[版本号] - 日期`。

## 维护约定（必读）

- **每次更新**（PR 合入或直推 `develop`）必须在「未发布」区追加条目，注明任务/PR 编号。
- CI（`changelog-check`）会校验每次 PR 与直推是否修改了本文件；确属不影响行为的改动（如纯格式化、CI 自身修复），可给 PR 打 `skip-changelog` 标签豁免。
- 条目按 `新增 / 变更 / 修复 / 文档 / 工程` 分类，一句话说清「改了什么 + 为什么」，并附任务键（WORD-NN）与 PR 编号。

## [未发布]

### 修复

- 主线验证问题 1（AC-02/AC-21 入场货币校验）：移除「档案已持有档位跳过购买」路径——0 货币仍可携高价背包免检入场；入场购买改为每局一次（事务引用按 runId 唯一，跨局各自扣款、同局重复确认被 LOADOUT 阶段守卫拦截），余额不足留在装载页并提示所需价格
- 主线验证问题 2（AC-17 核心搜刮图形化）：对局地图新增按本局计划生成的可点击容器实体（数量读 GameConfig.match_container_count，容器类型读配置数据；点击即搜索该容器并携带产出，已完成容器禁用标记不重复搜索）；修复入场后局内按钮停留在禁用态的问题（RUN_INIT -> IN_RUN_LOCKED 无事件，改为表现层每帧轮询阶段变化刷新）；搜索产出实例 id 加 runId 前缀（修复第二局同容器携带被实例幂等静默拒绝）
- 主线验证问题 3（AC-10/AC-11 双计时）：RunSessionService/ExtractService 的 tick 用 int(delta) 截断帧级浮点增量（每帧 ~0.016s 全部丢失）导致总时间与撤离读条停滞——改为浮点累积满整秒再扣减，余量随局/每次撤离开始复位（INV-14）；HUD 撤离读条总量改读配置（不再硬编码 15 秒）
- 伴随测试修正：test_container_search_wiring 多局复位用例改走合法撤离流程（旧用例依赖无阶段守卫的确认入场）；test_telemetry_wiring 出售价值解析改经物品定义（解耦编排器内部实例 id 命名）

### 测试

- 新增回归用例：0 货币已持有档位入场拦截、每局重复扣款、双确认防护（test_profile_loadout_wiring）；帧级浮点计时累积与余量复位（test_run_session_service/test_extract_service）；本局容器计划与按容器搜索幂等（test_container_search_wiring/test_telemetry_wiring）；地图容器实体 GUI 可点击（tests/integration/test_map_containers.gd，全局 EventBus 进程级单例下一局一套件）

### 变更

- WORD-40 首页 HUD 重构：顶栏左侧改为基础属性区——货币（金币图标+数值）与生命/氧气百分比条（像素图标+条内百分比，当前为占位常量，生命/属性域为未来方向）；仓库/背包改为右上角圆形像素按钮触发（仓库带数量徽标，背包点按 toast 档位），功能链不变（feat/lobby-home-ui）
- WORD-40 弹出窗口尺寸调整为 720×1260（project.godot window override；设计画布保持 1080×1920，运行缩放 2/3，6px 像素颗粒映射为 4 物理像素保持锐利）（feat/lobby-home-ui）
- WORD-40 首页视觉 V0.1：按示意草图重构局外主页布局——顶部三属性栏（货币/仓库/背包档位）、中部 2.5D 俯视像素基地（支持长按拖动平移，带活动范围钳位）、背包+安全箱格阵（红框列）、菜园/工坊/出击/市场/科技快捷按钮；仓库出售移入仓库弹窗，货币/仓库/出售/开始一局功能链与事件接线保持不变，`%StartButton` 等测试契约节点名不变（feat/lobby-home-ui）
- WORD-40 首页 UI 全面接入统一像素管线：新增 PixelUiKit（低分辨率框架 -> 整倍最近邻放大 -> 9-slice 凸台/内嵌 StyleBoxTexture 与圆形按钮整图），属性栏/格阵/快捷按钮/弹窗与 2.5D 基地共用同一颗粒密度；按钮文字经线性过滤子标签承载保持平滑；快捷按钮贴底对齐并收紧间距，格阵放大至 150px 并压缩面板内边距（feat/lobby-home-ui）

### 新增

- WORD-40 程序化像素画具 PixelArtKit 与首页基地视图 BaseView：低分辨率画布 + 整数倍最近邻放大实现像素化 2.5D，主屋/仓库棚/菜园/水塔/旗杆等元素与旗帜/信标轻量动画，纯表现无业务（feat/lobby-home-ui）
- WORD-40 开发辅助工具 tools/lobby_preview.gd：窗口模式实例化指定页面并截图到 reports/，便于 UI 迭代自查（feat/lobby-home-ui）

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
