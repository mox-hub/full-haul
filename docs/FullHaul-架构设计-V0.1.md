# FullHaul 游戏行为域拆分、核心状态机与基础设施分层设计（V0.1-baseline-02 返工版）

> 交付物：本文件为《满载而归（FullHaul）》V0.1 架构设计文档（返工版）。本文档只做设计拆分建议，不修改任何工程代码。
>
> 返工依据：本版依据 Task-审核 对首版的审核意见（WORD-9，P0-1~P3-2）修订；并以可获取的《轻量格子搜撤游戏 Prototype V0.1 项目规范 V0.1-baseline-02》为唯一范围基线。
>
> 冲突声明（对应审核 P0-3，符合规范 9.3）：WORD-5/WORD-8 任务说明中的「覆盖遭遇战斗、受伤/死亡、任务/社交/成长」等要求与 V0.1 规范 1.3/3.2/3.3 的 MUST NOT 冲突。按规范 9.3「任务说明与本文冲突时，以本文为准并报告冲突」，本版将战斗、敌人、任务、社交/匹配、成长、玩家受伤/死亡全部降级为「未来方向占位」，不进入 V0.1 域清单、核心状态机、事件流与最小切片；并在此向产品负责人/项目经理报告该冲突，由变更控制（规范 9.2）修正任务说明，或由产品负责人明确「战斗/AI 仅作未来方向描述、不进入 V0.1 实现」后本版方可最终归档。
>
> 核对说明：既有 Godot 工程路径（`E:\PROJECT_NEW\Obsidian\full-haul`）当前尚未确认，GitHub 仓库 `mox-hub/full-haul` 目前仅有空 README；工程目录/场景/脚本/版本的核对仍为实施前置阻塞（对应 P3-1），需项目经理提供工程接入。本文档基于规范与通用 Godot 实践给出推荐基线，接入实际工程后以其既有约定为准，未补默认值处一律以「待核对」标注。

---

## 0. 设计目标与原则

- 目标：将 V0.1 强制功能链所覆盖的游戏行为按领域拆分，明确边界与依赖；设计符合规范 4.2/4.3 的核心状态机与事件流；定义支撑 V0.1 的最小基础设施分层；给出 Godot 目录/场景/脚本组织与数据驱动、事件总线建议；输出 V0.1 最小切片、实施顺序、风险清单、验收标准。
- 原则：
  1. 领域单向依赖：表现层 → 应用编排层 → 领域层 → 数据/存档层；禁止反向依赖；领域间不得形成环。
  2. 领域层零 Godot 节点依赖（纯数据/纯逻辑，可独立测试）。
  3. 一切状态通过事件总线流转，模块间不直接持有对方实例（依赖注入 + 事件订阅）。
  4. 可替换、可独立测试为模块设计第一要求。
  5. 严格对齐 V0.1 规范范围：只覆盖规范 1.2 强制功能链，不引入 1.3/3.2/3.3 禁止域；「为以后预留完整系统」的过度设计不进入 V0.1（对应规范 P-03/P-04、11.1 与审核 P2-3）。

---

## 1. 行为域拆分与边界

V0.1 域清单严格以规范 1.2 强制功能链与 3.1 范围内内容为准；战斗/AI/任务/社交/成长/玩家生死仅保留为「未来方向占位」（仅接口占位，MAY，不进入 V0.1 实现），见 §1.2。

### 1.1 V0.1 正式域清单

| 域（Domain） | 职责 | 关键边界 / 依赖 | 可独立测试 |
|---|---|---|---|
| Profile / Player（局外账户） | 货币账本、仓库物品、已购/已选背包与装载引用 | 依赖 Transaction、Warehouse、DataLayer；不含生死/属性 | ✅ |
| Loadout（入场装载） | 背包购买/选择、货币校验与扣款、绑定本局背包（BackpackOffer） | 依赖 Profile、Transaction、RunState | ✅ |
| RunSession（局内状态） | 每局 Run 实例：runId、阶段、双计时、完成容器数、settled；一局一实例 | 被多数域引用；经接口注入，禁止全局静态单例 | ✅ |
| Loot / Container（容器与搜集） | 容器搜索子状态机、未知遮罩、逐件揭晓、完成计数（幂等） | 依赖 Item、GridInventory、ContainerState、Config | ✅ |
| Item & Inventory（物品与背包） | 物品定义/实例、背包/安全箱两个独立格子、放置校验、移动/旋转/丢弃 | 依赖 ItemDefinition/ItemInstance、GridInventory | ✅ |
| Extract（撤离） | 撤离锁定/解锁、15 秒撤离计时、成功/失败判定 | 依赖 RunSession | ✅ |
| Settlement（结算） | 成功/失败结算、单次结算幂等、结果流转至局外 | 依赖 RunSession、Profile、Warehouse | ✅ |
| Warehouse（仓库） | 带回物品入库、物品出售、原子事务 | 依赖 ItemInstance、Profile、Transaction | ✅ |
| Economy / Transaction（经济/事务） | 货币变动（购买扣款/出售加款/结算）、事务防重与诊断 | 被 Profile/Loadout/Warehouse 依赖；单一来源 | ✅ |
| Config & Telemetry（配置与遥测） | 集中配置加载（6.1 单一来源）、事件埋点、日志 | 无领域依赖，被各处消费 | ✅ |

> 说明：首版的 Player(生死)/Combat/AI/Quest/Social/Economy(成长) 域，按审核 P0-1 与规范 1.3/3.2/3.3 从 V0.1 正式域清单移除，仅作为未来方向占位（见 §1.2）。「Economy/Progression」拆分为「Economy/Transaction（货币事务）」与「Progression（成长，未来占位）」，「Save」拆分并入「Profile/Warehouse/DataLayer（局外数据）」与「DataLayer（持久化）」。

### 1.2 未来方向占位（MAY 仅接口，禁止 V0.1 实现）

| 未来域 | 长期方向（规范 3.3 记录） | V0.1 要求 |
|---|---|---|
| Combat / Enemy（战斗/敌人） | 未来危险通过事件与选项加入，不默认扩展为战斗系统 | 禁止实现战斗、敌人、武器、生命、伤害、死亡流程；MUST NOT 进入状态机/事件流/切片 |
| Player 生存（受伤/死亡） | 未来危险事件 | 禁止生命/伤害/死亡状态 |
| Progression（成长） | 搜索速度、移动效率、危险判定、出售费率；背包/安全箱按等级解锁购买权限 | 禁止等级、解锁、成长效果；仅完成购买/选择/扣款链 |
| Quest（任务） | 禁止 | 禁止 V0.1 实现 |
| Social / Matchmaking（社交/匹配） | 禁止 | 禁止 V0.1 实现 |
| Multiplayer（多人） | 未来方向 | 仅作未来演进记录，不进入 V0.1 接口承诺（对应审核 P3-2） |

依赖方向：`Loadout → Profile/RunSession`；`RunSession ← Loot/Extract/Settlement`；`Loot → Item → Config`；`Extract/Settlement → RunSession`；`Settlement/Warehouse → Profile/Transaction`；`Warehouse → ItemInstance`；`Config/Telemetry` 被各处消费。所有域经事件总线消费/发布领域事件，域间不直接互调，领域依赖表无环。

---

## 2. 核心循环状态机 / 事件流

按审核 P0-2 与规范 4.2/4.3 重建。V0.1 核心循环是「局外→购买背包→进入地图→搜索容器→揭晓→整理→完成 5 容器→撤离→结算→仓库→出售→货币→再开局」，无战斗/死亡。

### 2.1 顶层状态机（对应规范 4.2）

```
[BOOT] ──加载成功──→ [OUT_OF_RUN]
   │                     │ 选择开始
   │ 加载失败            ▼
   └──→ [ERROR]       [LOADOUT] ──取消──→ [OUT_OF_RUN]
						 │ 确认并扣款成功
						 ▼
					 [RUN_INIT] ──初始化成功──→ [IN_RUN_LOCKED]
													│ 完成数≥5
													▼
											[IN_RUN_EXTRACTABLE] ──开始撤离──→ [EXTRACTING]
													│ 总时间=0                      │ 撤离读条完成
													▼                              ▼
											  [RUN_FAILED]                    [RUN_SUCCEEDED]
													└──────────┬───────────────────┘
															   ▼
														  [SETTLED] ──确认──→ [OUT_OF_RUN]
```

- `BOOT`：加载配置与局外数据；成功→`OUT_OF_RUN`，失败→`ERROR`。
- `OUT_OF_RUN`：查看仓库、出售、进入准备；选择开始→`LOADOUT`。
- `LOADOUT`：购买/选择背包、校验货币、扣款绑定；确认且扣款成功→`RUN_INIT`；取消→`OUT_OF_RUN`（规范 AC-02）。
- `RUN_INIT`：创建唯一 Run、容器、物品与双计时状态；完成数=0、撤离锁定、settled=false（规范 AC-03）。
- `IN_RUN_LOCKED`：完成数<5；搜索、整理、丢弃；不可撤离；完成数≥5→`IN_RUN_EXTRACTABLE`；总时间=0→`RUN_FAILED`（INV-07）。
- `IN_RUN_EXTRACTABLE`：完成数≥5；继续搜索/整理或开始撤离；开始撤离→`EXTRACTING`；总时间=0→`RUN_FAILED`。
- `EXTRACTING`：撤离读条与总计时并行推进；读条先完成→`RUN_SUCCEEDED`；总时间先为0→`RUN_FAILED`（INV-08）。
- `RUN_SUCCEEDED`：执行一次成功结算；→`SETTLED`。
- `RUN_FAILED`：执行一次失败结算；→`SETTLED`。
- `SETTLED`：展示结果并持久化局外结果；确认→`OUT_OF_RUN`（INV-09 结算幂等）。
- `ERROR`：显示错误、保留诊断；不得吞错后污染数据（恢复策略为 TBD，规范 4.2）。

### 2.2 容器搜索子状态机（对应规范 4.3）

```
[UNOPENED] ──首次打开──→ [MASKED] ──开始揭晓──→ [REVEALING] ⇄ [PARTIALLY_REVEALED]
   │                          │                      │              │
   └── 未打开，不得暴露身份      │                      └──逐件揭晓──┘
							   └── 全部揭晓完成 → [COMPLETED]（首次进入 +1，幂等 INV-06）
```

- `UNOPENED`：容器未打开；不得提前暴露物品身份、品质或价值。
- `MASKED`：显示物品总数与每件物品当前方向完整占格；同尺寸视觉一致；禁止剪影/造型蒙版；不得泄露身份/类别/品质/价值（INV-05，AC-04/AC-18）。
- `REVEALING`：正在对某件物品计时；耗时由品质决定（0.5/1/2/3/5 秒，暂定）；搜索顺序为 TBD-03。
- `PARTIALLY_REVEALED`：已有已揭晓物品仍有遮罩物品；搜索能否中断/恢复为 TBD-02。
- `COMPLETED`：揭晓序列全部完成；首次进入时完成容器计数 +1，同一容器不重复计数（INV-06，AC-06）。

> TBD 提醒：容器内揭晓顺序（TBD-03）、搜索中断/恢复（TBD-02）、同刻计时优先级（TBD-04）均为规范未确定事项，本设计不填默认值，实施依赖处必须停工提问（规范 10.1）。

### 2.3 关键事件流（事件总线消息）

- `OutOfRunEntered / StartMatchRequested`（进入局外/请求开始）
- `BackpackPurchased { offerId, price, balanceBefore, balanceAfter }`（购买扣款，INV-12）
- `RunInitialized { runId, matchDuration=180, completedCount=0, extractLocked=true, settled=false }`（AC-03）
- `ContainerOpened { containerId, unknownCount, shapes }`（INV-05）
- `ItemRevealStarted { containerId, instanceId, rarity, waitTime }`（品质揭晓计时）
- `ItemRevealed { containerId, instanceId, definitionId, rarity, value, size }`
- `ContainerCompleted { containerId }`（首次完成，幂等计数 INV-06）
- `ItemPlaced / ItemMoved / ItemRotated / ItemDropped { instanceId, from, to }`（格子原子操作，INV-01~05）
- `ExtractUnlocked { completedCount=5 }` / `ExtractLocked { completedCount<5 }`（INV-07）
- `ExtractStarted { remainingExtractionTime=15 }`（INV-08）
- `RunSucceeded { runId, carriedItemIds }`（INV-10）
- `RunFailed { runId, safeItemIds }`（INV-11）
- `RunSettled { runId }`（结算幂等，INV-09）
- `WarehouseItemAdded { instanceId }` / `ItemSold { instanceId, price, balanceBefore, balanceAfter }`（INV-12）
- `CurrencyChanged { delta, balanceBefore, balanceAfter }`
- 遥测域订阅上述全部事件做埋点（不得作为产品规则来源，规范 6.4）。

> 删除首版的 CombatStarted/CombatResolved/HealthChanged/ActorDied 等战斗/生命/死亡事件（审核 P0-2）。

---

## 3. 基础设施分层与接口原则

按审核 P2-3 收敛为支撑 V0.1 功能链的最小分层，不引入五层 + DI 容器 + 服务定位的完整框架；仅保留必要的接口注入与事件总线。

| 层 | 内容 | 可替换 / 可独立测试 |
|---|---|---|
| 表现层（Presentation） | 场景、节点、动画、UI、输入映射 | 可替换；依赖领域/应用层接口 |
| 应用编排层（Application/Orchestration） | 用例/编排器：入场扣款、对局初始化、结算流转 | 可替换；测试用 mock 依赖 |
| 领域层（Domain） | 纯逻辑：顶层状态机、搜索子状态机、格子校验、结算规则 | ✅ 完全独立可测（不依赖 Godot） |
| 数据/存档层（Data） | 配置加载、局外数据读写（仓库/货币/背包）、序列化 | 可替换存储实现（JSON/二进制/云）；跨重启持久化按 TBD-12 |
| 工具与测试层（Tools/Tests） | 配置校验、测试夹具、GdUnit/GUT 用例 | ✅ |

接口原则：每层暴露最小接口（如 `IRunStateStore`、`IEventBus`、`IConfigLoader`、`IProfileRepository`），领域层只依赖接口；测试通过替换接口实现注入 mock。**不做全局静态单例承载运行态状态**：`RunSession`/`RunState` 每局一个实例，经接口注入（审核 P1-3）；事件总线与配置加载可作为 Autoload 基础设施，但不承载业务运行态。

---

## 4. Godot 工程组织建议（待与既有工程核对后落地）

> 待核对：既有工程的目录结构、场景命名、脚本语言（GDScript/C#）与 Godot 版本（审核 P3-1）。以下为推荐基线，接入实际工程后以其既有约定为准。

- 建议结构（`res://`）：
  - `scenes/`（表现层场景：`lobby/`、`match/`、`container/`、`grid/`、`ui/`）
  - `scripts/domain/`（纯逻辑，禁 `Node` 依赖）
  - `scripts/application/`（编排/服务）
  - `scripts/presentation/`（节点脚本、控制器）
  - `data/`（集中配置：`GameConfig`、物品/容器/品质/测试经济等，JSON/CSV/Resource）
  - `autoload/`（事件总线、配置加载；不承载业务运行态）
  - `tests/`（GdUnit/GUT 用例，按域分目录，映射 AC/INV）
- 事件总线：用 `Autoload` 单例 + 信号/自定义 `EventBus`，领域事件用数据对象而非直接信号（便于跨层、事务化与防重）。业务运行态（Run/货币/仓库）不放在 Autoload 全局单例，而由每局/每局外实例承载并经接口注入（审核 P1-3）。
- 数据驱动：所有平衡/内容/测试参数来自集中配置单一来源（规范 6.1、INV-16、AC-16）；V0.1 只保留规范 6.2 最小语义实体的配置（见 §5），配置表仅含 V0.1 实体（审核 P2-2）。修改配置不改核心算法/UI。
- 单机→多人演进：仅作为未来方向记录，不进入 V0.1 接口承诺（审核 P3-2）。V0.1 以单机实现保证功能链闭环即可。

---

## 5. 数据模型（对接规范 6.2，单一来源 6.1）

数据模型以规范 6.2 最小语义实体为底座，V0.1 只保留功能链内实体；Enemy/Quest 等非 V0.1 表不建立（审核 P2-2）。

| 实体 | 关键字段 / 职责 | 约束 |
|---|---|---|
| GameConfig | matchDuration=180、extractionDuration=15、requiredCompletedContainers=5、initialCurrency=100000、rarityRevealDurations、revealFlipDuration、baseGridCellSize、containerItemCountRange | 集中配置入口；单一来源（INV-16） |
| ItemDefinition | definitionId、name、rarity、width、height、value、colorSemantic | 定义与实例分离；尺寸正整数 |
| ItemInstance | instanceId、definitionId、orientation、location、gridX/gridY | instanceId 唯一；同一实例只属一个位置（INV-01） |
| ContainerState | containerId、itemInstanceIds、revealState、completed、counted | 遮罩形状与最终尺寸一致；counted 防重复计数（INV-06） |
| GridInventory | inventoryId、ownerType、width、height、placements | 合法性校验；背包/安全箱/仓库语义分离（INV-04） |
| BackpackOffer | offerId、displayName、price、gridWidth、gridHeight、availability | V0.1 三档：4×4/1000、5×5/2500、6×6/5000；购买校验与扣款 |
| RunState | runId、phase、remainingMatchTime、remainingExtractionTime、completedContainerCount、settled | 一局一实例；状态单向受控；settled 防重复结算（INV-09） |
| PlayerProfile | currency、warehouseItemIds、loadout 引用 | 局外状态与局内临时状态分离（INV-13） |
| Transaction | transactionId、type、amount/itemIds、before/after、status | 购买/出售/结算防重与诊断 |
| ContainerTierConfig | tier、rarityWeights | C1~C5 仅决定产出权重；每件独立抽取；权重合计100%（AC-19） |
| ContainerType | typeId、displayName、tier、gridWidth、gridHeight、iconId、mapAvailability | 类型与 Tier 分离；GridSize 由类型配置，不由 Tier 推导（INV-15） |
| SafeContainerConfig | gridWidth=2、gridHeight=2、defaultOwned=true、price=0 | V0.1 测试配置 |
| VisualConfig | designWidth=1080、designHeight=1920（竖屏 9:16，2026-08 WORD-26 起生效，本文旧值 1920×1080 横屏已废弃）、baseGridCellSize=64、revealFlipDuration=250~400ms、semanticColors | 响应式（canvas_items+expand）；品质 HEX 见 PixelUiKit.RARITY_COLORS（epic=红色系系有意决策）；渲染器 gl_compatibility + 原生平滑卡通画风为 2026-08-27 视觉升级决策（见 changelog 与 docs/art/art-pipeline.md） |

持久化边界（审核 P1-2）：V0.1 持久化范围 = **同一应用运行周期内**多局正确的局外结果（仓库/货币/背包选择，规范 5.5、INV-14）；跨重启持久化范围、存储位置与迁移策略按 TBD-12 待产品决策，不在 V0.1 承诺内。Warehouse/Loadout 由 Profile/Warehouse/Transaction 域承载，不再依赖模糊的「Save(局外成长)」声明。

---

## 6. V0.1 最小架构切片

V0.1 切片严格覆盖规范 1.2 强制功能链，不含战斗/AI/任务/社交/成长：

1. **配置加载 + 事件总线**（Autoload 基础设施，单一来源）
2. **顶层状态机**（BOOT/OUT_OF_RUN/LOADOUT/RUN_INIT/IN_RUN_LOCKED/IN_RUN_EXTRACTABLE/EXTRACTING/RUN_SUCCEEDED/RUN_FAILED/SETTLED/ERROR）
3. **Profile + Loadout**（货币、仓库、背包购买/选择/扣款，AC-02/AC-21）
4. **RunSession**（每局实例、双计时、完成数、settled，AC-03）
5. **Item & Inventory**（定义/实例、背包+安全箱格子、放置校验、移动/旋转/丢弃，AC-07/AC-08）
6. **Loot / Container**（搜索子状态机、遮罩、逐件揭晓、完成计数幂等，AC-04/AC-05/AC-06/AC-17/AC-18/AC-19/AC-20）
7. **Extract**（锁定/解锁、15 秒撤离、并行计时，AC-09/AC-10/AC-11）
8. **Settlement + Warehouse + Transaction**（成败结算、入库、出售、货币，AC-12/AC-13/AC-14/AC-15）
9. **Telemetry**（基础埋点，不构成产品规则来源）

> 多人演进不进入 V0.1 切片（审核 P3-2）；战斗/AI/成长等仅未来占位，不进入切片（审核 P0-1）。

---

## 7. 实施顺序

1. 接入并核对既有 Godot 工程（目录/版本/约定）→ 消除「待核对」项（需项目经理提供工程接入，P3-1）
2. 搭配置加载 + 事件总线 + 顶层状态机骨架 + 单元测试（地基）
3. Profile + Loadout（购买/选择/扣款）
4. RunSession（每局实例、双计时）
5. Item & Inventory（格子与放置校验）
6. Loot / Container（搜索子状态机、揭晓、计数）
7. Extract（锁定/解锁、撤离计时）
8. Settlement + Warehouse + Transaction（结算/入库/出售/货币）
9. Telemetry + 表现层接场景/UI，跑通强制功能链闭环
10. 连续多局与边界回归（AC-15、INV-14）

每步先领域层测试（映射 AC/INV），再接表现层；前置工作包未通过验收，后置包不得开始（规范 11.1）。

---

## 8. 测试策略（对接规范 AC / INV，审核 P2-1）

| 域 | 对应不变量 | 对应验收用例 |
|---|---|---|
| 顶层状态机 | INV-06/07/08/09/13/14 | AC-02/03/06/09/10/11/12/13/15 |
| 容器搜索子状态机 | INV-05/06 | AC-04/05/06/17/18/19 |
| 格子/物品 | INV-01~05 | AC-07/08 |
| 结算/仓库/出售/货币 | INV-09~12/13 | AC-12/13/14/15 |
| 配置单一来源 | INV-15/16 | AC-16/20/21/22 |
| 连续多局隔离 | INV-14 | AC-15 |
| 受保护核心区/Git | — | AC-23/24 |

最低覆盖按规范第 7 节逐项执行：复制/无误失（INV-02/03）、结算幂等（INV-09）、货币守恒（INV-12）、多局隔离（INV-14）为强制回归项。

---

## 9. 风险清单

| 风险 | 等级 | 缓解 |
|---|---|---|
| 既有工程结构/版本与本文档假设不符（P3-1） | 高 | 实施前先接入核对既有工程；需项目经理提供工程接入 |
| 任务说明与规范冲突未走变更控制（P0-3） | 高 | 本版已报告冲突；归档前需产品负责人/变更控制明确战斗/AI 为未来方向 |
| 搜索中断/恢复、揭晓顺序、同刻计时优先级为 TBD | 高 | 依赖处停工提问，不填默认值（规范 10.1） |
| 领域层与表现层耦合 | 中 | 代码评审强制领域层禁 `Node` 依赖 + 独立测试 |
| 全局静态状态（Run/货币）导致多局污染 | 中 | RunSession/Profile 每实例注入，禁止全局单例承载运行态（P1-3） |
| 数据驱动配置未单一来源 | 中 | 统一配置加载器 + 配置校验工具（INV-16） |
| 结算/出售/扣款非幂等或货币不守恒 | 中 | Transaction 防重 + INV-09/12 回归 |
| 跨重启持久化范围未定 | 低 | 明确 V0.1 只保证运行周期内；跨重启按 TBD-12 |

---

## 10. 验收标准

- [ ] 行为域覆盖规范 1.2 强制功能链与关键持久化边界（局外→购买背包→对局→容器→撤离→结算→仓库→出售→货币→再开局）
- [ ] 状态机按规范 4.2/4.3 闭合：顶层含 BOOT/ERROR/OUT_OF_RUN/LOADOUT/RUN_INIT/IN_RUN_LOCKED/IN_RUN_EXTRACTABLE/EXTRACTING/RUN_SUCCEEDED/RUN_FAILED/SETTLED；容器含 UNOPENED/MASKED/REVEALING/PARTIALLY_REVEALED/COMPLETED；无循环依赖、无隐式全局状态
- [ ] 事件流补齐 背包购买/扣款、撤离锁定/解锁、容器完成计数、仓库入库、出售、货币变动、结算幂等；删除战斗/生命/死亡事件
- [ ] 数据模型对接规范 6.2 最小语义实体；配置单一来源（6.1）；V0.1 只保留功能链内实体
- [ ] 分层收敛为支撑 V0.1 的最小分层；未来域仅接口占位（P2-3）
- [ ] 测试策略映射 AC-01~AC-24 与 INV-01~16（P2-1）
- [ ] 明确最小切片、实施顺序、多人演进仅作未来方向（P3-2）
- [ ] 既有 Godot 工程与规范基线已核对（「待核对」项清零）后才进入实施
- [ ] 最终归档前必须获得 Haoran Li 验收确认；本版经 Task-审核 复审通过后再建议归档

---

## 待核对 / 待决策项汇总（实施前必须确认）

1. 既有 Godot 工程实际目录/场景/脚本组织与命名约定、Godot 版本、脚本语言（GDScript/C#）——需项目经理提供工程接入（P3-1）。
2. WORD-5/WORD-8 任务说明中「战斗/受伤/死亡/任务/社交/成长」要求与规范冲突的变更控制处理（P0-3）：请产品负责人明确战斗/AI 仅作未来方向描述、不进入 V0.1 实现。
3. 规范 TBD-02（搜索中断/恢复）、TBD-03（容器内揭晓顺序）、TBD-04（同刻计时优先级）、TBD-12（跨重启持久化）：依赖处停工提问，不填默认值。
4. 配置表格式（JSON/CSV/Resource）与存档格式偏好——按 TBD-12 待产品决策。
