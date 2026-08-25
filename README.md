# FullHaul（满载而归）V0.1 基础框架

基于 Godot 4.7 的《满载而归》FullHaul V0.1 工程基础框架。本框架依据《FullHaul-架构设计-V0.1.md》
（返工版）搭建，实现架构文档 §6 的最小架构切片地基（切片 1-2），并完成
领域层接口骨架与容器搜索子状态机的「域拆分」（WORD-24）。

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
│   │   └── profile_repository_interface.gd # 接口：IProfileRepository
│   ├── application/          # 应用编排层（用例/编排器，待后续切片）
│   └── presentation/         # 表现层（节点脚本/控制器，待后续切片）
├── scenes/                   # 表现层场景
│   ├── main.tscn / main.gd   #   工程主场景（启动引导入口）
│   ├── lobby/                #   局外（待后续切片）
│   ├── match/                #   对局（待后续切片）
│   ├── container/            #   容器（待后续切片）
│   ├── grid/                 #   格子（待后续切片）
│   └── ui/                   #   通用 UI（待后续切片）
├── data/
│   └── GameConfig.gd         # 全局配置数据（V0.1 最小语义实体，规范 6.2）
└── tests/
    ├── domain/               # 领域层地基测试（GdUnit4，映射 AC/INV）
    │   ├── test_domain_smoke.gd          # 领域层冒烟测试（独立可跑）
    │   ├── test_run_state.gd             # RunState 局内状态（INV-09 幂等）
    │   ├── test_top_level_state_machine.gd  # 顶层状态机（AC-02/03/09-15）
    │   ├── test_container_search_state_machine.gd # 容器搜索子状态机（INV-05/06）
    │   ├── test_game_config.gd           # 配置单一来源（INV-15/16，AC-16/20-22）
    │   ├── test_player_profile.gd        # 局外账户（INV-12/13，AC-21）
    │   └── test_infrastructure.gd        # EventBus/ConfigLoader 基础设施
    ├── integration/          # 集成测试（待后续切片）
    └── fixtures/             # 测试夹具（待后续切片）
```

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
# 1. 冒烟测试（领域层纯逻辑，独立可跑）
godot --headless --path . --script res://tests/domain/test_domain_smoke.gd

# 2. 启动工程（Autoload + 主场景引导）
godot --headless --path . --quit
```

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
- [ ] 切片 3：Profile + Loadout（购买/选择/扣款）
- [ ] 切片 4：RunSession（双计时、完成数）
- [ ] 切片 5：Item & Inventory（格子与放置校验）
- [ ] 切片 6：Loot / Container（搜索子状态机、揭晓、计数）
- [ ] 切片 7：Extract（锁定/解锁、撤离计时）
- [ ] 切片 8：Settlement + Warehouse + Transaction（结算/入库/出售/货币）
- [ ] 切片 9：Telemetry + 表现层接场景/UI，跑通强制功能链闭环

> TBD 停工红线：涉及规范 TBD-02/03/04/12 的依赖处必须停工提问，不得私自补默认值。