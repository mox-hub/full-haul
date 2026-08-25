# FullHaul（满载而归）V0.1 基础框架

基于 Godot 4.7 的《满载而归》FullHaul V0.1 工程基础框架。本框架依据《FullHaul-架构设计-V0.1.md》
（返工版）搭建，实现架构文档 §6 的最小架构切片地基（切片 1-2），完成
领域层接口骨架与容器搜索子状态机的「域拆分」（WORD-24），并交付玩法验证用的
基础页面 V0（应用编排层 + 表现层占位界面，WORD-26）。

## 目录结构（架构文档 §4 建议）

```
res://
├── autoload/                 # Autoload 基础设施（不承载业务运行态）
│   ├── EventBus.gd           #   全局事件总线（事件流转唯一通道）
│   └── ConfigLoader.gd       #   全局配置加载器（配置单一来源 INV-16）
├── scripts/
│   ├── domain/               # 领域层（纯逻辑，零 Node 依赖，可独立测试）
│   │   ├── domain_events.gd  #   领域事件定义（纯数据，全局共享）
│   │   ├── run_state.gd      #   局内状态模型（RunState，INV-09 幂等）
│   │   ├── player_profile.gd #   局外账户模型（PlayerProfile）
│   │   ├── top_level_state_machine.gd     # 顶层状态机（规范 4.2，域拆分接线）
│   │   ├── container_search_state_machine.gd # 容器搜索子状态机（规范 4.3，Loot 域）
│   │   ├── services/         # 领域服务接口骨架（域拆分，架构 §1.1）
│   │   │   ├── i_loadout_service.gd          # 接口：ILoadoutService
│   │   │   ├── i_run_session_service.gd      # 接口：IRunSessionService
│   │   │   ├── i_item_inventory_service.gd   # 接口：IItemInventoryService
│   │   │   ├── i_container_search_service.gd # 接口：IContainerSearchService
│   │   │   ├── i_extract_service.gd          # 接口：IExtractService
│   │   │   ├── i_settlement_service.gd       # 接口：ISettlementService
│   │   │   ├── i_warehouse_service.gd        # 接口：IWarehouseService
│   │   │   └── i_transaction_service.gd      # 接口：ITransactionService
│   │   ├── event_bus_interface.gd      # 接口：IEventBus
│   │   ├── config_loader_interface.gd  # 接口：IConfigLoader
│   │   ├── run_state_store_interface.gd# 接口：IRunStateStore
│   │   ├── profile_repository_interface.gd # 接口：IProfileRepository（存档）
│   │   └── repositories/    # 仓储接口（WORD-30，领域层契约，不含数据库细节）
│   │       ├── iconfig_data_repository.gd    # 接口：IConfigDataRepository（配置）
│   │       ├── irun_result_repository.gd     # 接口：IRunResultRepository（结算/事务）
│   │       └── irun_snapshot_repository.gd   # 接口：IRunSnapshotRepository（运行时，可选）
│   ├── application/          # 应用编排层（WORD-26）
│   │   └── run_flow_orchestrator.gd #  一局流程编排器（表现层用例入口）
│   ├── infrastructure/       # 基础设施/数据层（WORD-30；数据库实现，遵循 WORD-8 分层）
│   │   └── db/              #   SQLite 数据库实现
│   │       ├── database_connector.gd            # 连接封装（user://data/fullhaul.db）
│   │       ├── database_initializer.gd          # 一键初始化 + 迁移（db/migrations）
│   │       ├── run_state_codec.gd               # RunState 阶段枚举<->字符串互转
│   │       ├── sqlite_config_data_repository.gd # IConfigDataRepository 实现
│   │       ├── sqlite_profile_repository.gd     # IProfileRepository 实现
│   │       ├── sqlite_run_result_repository.gd  # IRunResultRepository 实现
│   │       └── sqlite_run_snapshot_repository.gd# IRunSnapshotRepository 实现
│   └── presentation/         # 表现层（WORD-26 基础页面 V0）
│       ├── page_router.gd    #   页面路由器（事件驱动页面切换）
│       ├── hud.gd            #   局内 HUD（生命/背包/撤离目标占位展示）
│       └── pages/            #   页面脚本
│           ├── lobby_page.gd       # 局外页
│           ├── loadout_page.gd     # 入场装载页（占位）
│           ├── match_page.gd       # 局内主页（搜集/撤离交互占位）
│           └── settlement_page.gd  # 结算页（成功/失败）
├── scenes/                   # 表现层场景
│   ├── main.tscn / main.gd   #   工程主场景（启动引导 + 组合根装配）
│   ├── lobby/                #   局外（lobby_page / loadout_page 占位场景）
│   ├── match/                #   对局（match_page / hud 占位场景）
│   ├── container/            #   容器（待后续切片）
│   ├── grid/                 #   格子（待后续切片）
│   └── ui/                   #   通用 UI（settlement_page 占位场景）
├── data/
│   └── GameConfig.gd         # 全局配置数据（V0.1 最小语义实体，规范 6.2）
├── db/                       # 系统数据库（WORD-30；SQLite 建表/迁移脚本）
│   ├── schema.sql            #   当前完整模式（一键全新建库参考）
│   ├── README.md             #   初始化/迁移操作说明
│   └── migrations/           #   增量迁移（001_initial_schema.sql）
├── docs/
│   └── database/             # 数据库设计文档（WORD-30）
│       ├── README.md         #   选型说明
│       └── schema-design.md  #   表结构/字段/索引/ER（配置/存档/运行时三类）
└── tests/
    ├── domain/               # 领域层地基测试（GdUnit4，映射 AC/INV）
    │   ├── test_domain_smoke.gd          # 领域层冒烟测试（独立可跑）
    │   ├── test_run_state.gd             # RunState 局内状态（INV-09 幂等）
    │   ├── test_top_level_state_machine.gd  # 顶层状态机（AC-02/03/09-15）
    │   ├── test_container_search_state_machine.gd # 容器搜索子状态机（INV-05/06）
    │   ├── test_game_config.gd           # 配置单一来源（INV-15/16，AC-16/20-22）
    │   ├── test_player_profile.gd        # 局外账户（INV-12/13，AC-21）
    │   └── test_infrastructure.gd        # EventBus/ConfigLoader 基础设施
    ├── application/          # 应用编排层接线测试（WORD-26）
    │   └── test_run_flow_orchestrator.gd # 一局流程用例编排（最小闭环/守卫/多局隔离）
    ├── integration/          # 集成测试（WORD-26）
    │   └── test_main_flow_smoke.gd       # 主场景端到端冒烟（真实 Autoload 黑盒驱动）
    ├── presentation/         # 表现层接线测试（WORD-26）
    │   └── test_page_router.gd           # 事件驱动页面切换/结算/HUD 复位
    └── fixtures/             # 测试夹具（待后续切片）
```

## 基础页面 V0（WORD-26）

界面按 **9:16 竖屏**设计，设计分辨率 **1080×1920**（短边 1080）：
`project.godot` 视口 1080×1920（桌面窗口以 540×960 打开、不可调大小，
移动端锁定竖屏）；`GameConfig.design_width/design_height` 同步为
1080/1920（视觉配置单一来源）。

玩法验证用的占位界面已接入：`main.tscn` 为组合根，装配应用编排层
（`RunFlowOrchestrator`）与表现层（四个页面 + `PageRouter`）。页面切换完全由
事件总线上的领域事件驱动；按钮只调用编排器用例，不触碰领域层状态。

- **局外页**（`OUT_OF_RUN_ENTERED`）：「开始一局」→ 入场装载。
- **入场装载页**（`START_MATCH_REQUESTED`，占位）：确认入场 / 取消返回。
- **局内主页**（`RUN_INITIALIZED`）：HUD（生命占位 / 背包占位 / 撤离目标 x/N /
  撤离读条视觉动画）+ 交互按钮（搜索容器占位 ×5 解锁撤离 → 开始撤离 →
  撤离读条完成占位 / 本局时间耗尽占位）。
- **结算页**（`RUN_SUCCEEDED` / `RUN_FAILED` / `RUN_SETTLED`）：成败展示与
  物品去向 → 完成结算 → 返回局外。
- **ERROR 态**：配置加载失败时展示启动失败页面（规范 4.2）。

任务描述中的「战斗」环节为 V0.1 规范外未来方向（架构审核 P0-1/P0-2，
战斗/生命事件已删除），界面未包含战斗交互；撤离双计时并行推进依赖
TBD-04（同刻优先级），V0.1 以占位按钮触发成败分支，不私自补默认值。

## 单元测试基建（WORD-25）

工程集成 **GdUnit4**（`addons/gdUnit4`，编辑器插件已启用）作为单元测试框架，
`tests/domain/` 下为领域层「地基测试」，按架构 §8 测试策略映射 AC/INV，
覆盖状态机、容器搜索、配置、账户与基础设施。领域层测试均为纯逻辑（零 Godot
节点依赖），可用 GdUnit4 命令行无头运行：

```bash
# 运行全部领域层地基测试（GdUnit4 无头模式）
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
     -a res://tests/domain --ignoreHeadlessMode

# 仅运行指定测试套件
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
     -a res://tests/domain/test_top_level_state_machine.gd --ignoreHeadlessMode
```

## 运行与验证

Godot 4.7+ 命令行验证（无 GUI）：

```bash
# 1. 运行全部测试（领域 + 应用/表现接线 + 主场景集成冒烟）
godot --headless --path . res://tests/test_runner.tscn

# 2. 启动工程（Autoload + 主场景引导，进入局外页）
godot --headless --path . --quit
```

图形界面跑通最小玩法流程（WORD-26 验收）：

```bash
godot --path .
```

1. 局外页点「开始一局」→ 入场装载页；
2. 「确认入场」→ 进入局内主页（HUD 显示撤离目标 0/5 锁定）；
3. 点「搜索容器（占位）」×5 → HUD 提示撤离已解锁，「开始撤离」变为可用；
4. 「开始撤离」→ HUD 出现撤离读条动画；点「撤离读条完成（占位）」→ 结算页
   显示「撤离成功」（或局内任意时刻点「本局时间耗尽（占位）」→「撤离失败」）；
5. 「完成结算」→「返回局外」→ 回到局外页，可再开下一局（runId 递增）。

## 系统数据库层（WORD-30）

选用 **SQLite**（嵌入式、本地单文件，与 Godot 工程兼容；Godot 侧经 `sqlite`
GDExtension 访问）。数据库设计文档与建表脚本已入库：

- 设计：`docs/database/README.md`（选型）、`docs/database/schema-design.md`
  （表结构/字段/索引/ER，配置/存档/运行时三类划分，与 WORD-27 CSV 对齐）。
- 脚本：`db/schema.sql`（当前完整模式）+ `db/migrations/`（增量迁移机制）。
- 分层：仓储接口定义于领域层（`scripts/domain/repositories/`），数据库实现位于
  基础设施层（`scripts/infrastructure/db/`），遵循 WORD-8 分层——领域/表现层
  只依赖接口，不感知数据库实现细节。

**一键初始化**：应用启动时由 `DatabaseInitializer` 打开 `user://data/fullhaul.db`
并自动应用 `db/migrations/` 下未执行的迁移（幂等）；或手动
`sqlite3 fullhaul.db < db/schema.sql`。详见 `db/README.md`。

> 说明：V0.1 持久化范围为同一应用运行周期内（TBD-12）；跨重启持久化策略待产品
> 决策。`sqlite` GDExtension 的接入与仓储数据库实现的实际接线（配置切换、事件
> 广播）在 WORD-31（阶段2）落地。

## 架构约束（开发规范要点）

1. **领域单向依赖**：表现层 → 应用编排层 → 领域层 → 数据/存档层；禁止反向依赖。
2. **领域层零 Godot 节点依赖**：`scripts/domain/` 内一律 `extends RefCounted`，
   不得引用 `Node`/Autoload 单例，保证可独立单元测试。
3. **事件驱动**：模块间通过事件总线流转领域事件（`DomainEvents` 定义），
   不直接持有对方实例（依赖注入 + 事件订阅）。
4. **禁止全局单例承载运行态**：`RunState`/`PlayerProfile` 等业务运行态一律
   每局/每局外实例化并经接口注入（`IRunStateStore` 等）；Autoload 只承载
   基础设施（事件总线、配置加载）。
5. **配置单一来源**：所有平衡/内容/测试参数读取 `GameConfig`，不硬编码。
6. **范围边界**：V0.1 只实现规范 1.2 强制功能链；战斗/AI/任务/社交/成长为
   未来方向占位，禁止实现。

## 待办切片（架构文档 §7 实施顺序）

- [x] 切片 1-2 地基：配置加载 + 事件总线 + 顶层状态机骨架 + 领域层接口
- [x] 域拆分（WORD-24）：各 V0.1 域的服务接口骨架 + 容器搜索子状态机（规范 4.3）
- [x] 基础页面 V0（WORD-26）：应用编排层 + 表现层占位界面，事件驱动接线，
      可跑通「进入一局 → 界面切换 → 结算」最小闭环（各域真实逻辑仍待切片 3-8 接入）
- [ ] 切片 3：Profile + Loadout（购买/选择/扣款）
- [ ] 切片 4：RunSession（双计时、完成数）
- [ ] 切片 5：Item & Inventory（格子与放置校验）
- [ ] 切片 6：Loot / Container（搜索子状态机、揭晓、计数）
- [ ] 切片 7：Extract（锁定/解锁、撤离计时）
- [ ] 切片 8：Settlement + Warehouse + Transaction（结算/入库/出售/货币）
- [ ] 切片 9：Telemetry + 表现层接场景/UI，跑通强制功能链闭环

> TBD 停工红线：涉及规范 TBD-02/03/04/12 的依赖处必须停工提问，不得私自补默认值。