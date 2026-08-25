# FullHaul 系统数据库设计文档（WORD-30）

> 数据库选型见 [`README.md`](./README.md)（SQLite，嵌入式本地单文件）。
> 本文档定义**表结构、字段、索引、ER 关系**，并按
> **配置数据 / 存档数据 / 运行时数据** 三类划分，与 WORD-27 CSV 字段对齐。
> 落地脚本：`db/schema.sql`（当前完整模式）+ `db/migrations/`（增量迁移）。

---

## 1. 设计原则

- **对齐架构（WORD-8）**：数据模型对接架构 §5 最小语义实体（ItemDefinition、
  ItemInstance、ContainerState、BackpackOffer、RunState、PlayerProfile、
  Transaction、ContainerType/TierConfig、SafeContainerConfig）；只建 V0.1
  功能链内实体，不为未来方向（战斗/成长/任务等）建表。
- **三类划分**：
  - **配置数据（A）**：静态、只读，启动时由配置加载器消费（单一来源 INV-16），
    与 WORD-27 道具/藏品/撤离点 CSV 字段对齐；
  - **存档数据（B）**：玩家进度、仓库/背包、结算与事务流水，V0.1 持久化范围为
    同一运行周期内（TBD-12）；
  - **运行时数据（C）**：一局内状态快照，可选（调试/回放用）。
- **分层解耦**：领域层只依赖仓储接口（`scripts/domain/repositories/`），数据库
  实现位于基础设施层（`scripts/infrastructure/db/`），不把引擎/连接细节泄露给
  领域/表现层（WORD-8）。
- **主键为业务字符串 id**（definition_id / instance_id / run_id 等），便于与
  领域对象与 CSV 直接映射；JSON 列（如 `carried_item_ids`、`rarity_weights`）
  承载结构化扩展，避免过度范式化。

---

## 2. ER 关系总览

```
【A 配置数据】                                        【C 运行时数据】
item_definition ──< item_instance                    run_snapshot 1─< container_state
container_type  ──< container_state                     │1─< item_instance
container_tier_config（独立，供产出权重查询）               │
backpack_offer  ──< player_profile(selected_offer)       └（每局快照，可选）

【B 存档数据】
player_profile 1─< warehouse_item
player_profile 1─< settlement_record
player_profile 1─< economy_transaction
```

| 关系 | 说明 | 基数 |
|---|---|---|
| player_profile → warehouse_item | 一个账户拥有多个仓库物品 | 1:N |
| player_profile → selected_backpack_offer_id | 账户当前选中一个背包档位（引用，非强 FK，可空） | N:1 |
| player_profile → settlement_record | 一个账户有多条结算记录 | 1:N |
| player_profile → economy_transaction | 一个账户有多条经济事务流水 | 1:N |
| item_definition → warehouse_item | 仓库物品引用道具定义 | 1:N |
| item_definition → item_instance | 道具定义可被实例化为局内物品 | 1:N |
| container_type → container_state | 容器状态引用容器/撤离点类型 | 1:N |
| run_snapshot → container_state | 一局含多个容器状态（级联删除） | 1:N |
| run_snapshot → item_instance | 一局含多个物品实例（级联删除） | 1:N |
| container_state → item_instance | 容器状态可含多个实例 | 1:N |

> 说明：配置数据为只读基线，存档/运行时通过外键引用；若 WORD-27 CSV 后续调整
> 字段，仅需同步配置表列与 CSV 表头映射，不影响存档/运行时结构。

---

## 3. 表结构明细

### A. 配置数据（静态）

#### 3.1 `item_definition` —— 道具 / 藏品定义

与 WORD-27「道具 CSV」「藏品 CSV」字段对齐（`category` 区分道具/藏品）。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| definition_id | TEXT | PK | 唯一 id（CSV「ID」列） |
| category | TEXT | NOT NULL, CHECK(item/collectible) | 道具 / 藏品 |
| name | TEXT | NOT NULL | 显示名 |
| rarity | TEXT | NOT NULL, CHECK(common..legendary) | 稀有度（对应揭晓耗时 INV-16） |
| width | INTEGER | NOT NULL, CHECK(>0) | 占格宽 |
| height | INTEGER | NOT NULL, CHECK(>0) | 占格高 |
| value | INTEGER | NOT NULL DEFAULT 0 | 基础价值 |
| stackable | INTEGER | NOT NULL DEFAULT 0 | 是否可堆叠 |
| effect_value | INTEGER | NULL | 功能道具效果数值（CSV「效果数值」） |
| series | TEXT | NULL | 藏品所属系列（CSV「所属系列」） |
| color_semantic | TEXT | NULL | 视觉语义色（品质 HEX 为 TBD，可空） |

索引：
- `idx_item_definition_rarity (rarity)` —— 按稀有度查询/权重表生成
- `idx_item_definition_category (category)` —— 按道具/藏品分组

#### 3.2 `container_type` —— 容器 / 撤离点类型

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| type_id | TEXT | PK | 类型 id |
| kind | TEXT | NOT NULL, CHECK(container/extract) | 普通容器 / 撤离点 |
| display_name | TEXT | NOT NULL | 显示名 |
| tier | TEXT | NOT NULL | 所属 Tier（C1~C5，仅决定产出权重 INV-15） |
| grid_width | INTEGER | NOT NULL, CHECK(>0) | 格子宽（由类型配置，不由 Tier 推导） |
| grid_height | INTEGER | NOT NULL, CHECK(>0) | 格子高 |
| icon_id | TEXT | NULL | 图标 |
| map_availability | TEXT | NULL | 地图可用性 |

索引：`idx_container_type_kind (kind)`

#### 3.3 `container_tier_config` —— 容器产出权重

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| tier | TEXT | PK | C1~C5 |
| rarity_weights | TEXT | NOT NULL | JSON，如 `{"common":60,...}`（合计 100%，AC-19） |

#### 3.4 `backpack_offer` —— 背包档位

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| offer_id | TEXT | PK | 如 backpack_4x4 / 5x5 / 6x6 |
| display_name | TEXT | NOT NULL | 显示名 |
| price | INTEGER | NOT NULL, CHECK(>0) | 价格（1000/2500/5000） |
| grid_width | INTEGER | NOT NULL, CHECK(>0) | 格子宽 |
| grid_height | INTEGER | NOT NULL, CHECK(>0) | 格子高 |

#### 3.5 `safe_container_config` —— 安全箱配置

单行表（`id=1`），V0.1 测试配置。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | INTEGER | PK, CHECK(id=1) | 恒为 1（单行） |
| grid_width | INTEGER | NOT NULL DEFAULT 2 | 格子宽 |
| grid_height | INTEGER | NOT NULL DEFAULT 2 | 格子高 |
| default_owned | INTEGER | NOT NULL DEFAULT 1 | 默认拥有 |
| price | INTEGER | NOT NULL DEFAULT 0 | 价格 |

### B. 存档数据

#### 3.6 `player_profile` —— 玩家局外账户（架构 §5 PlayerProfile）

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| profile_id | TEXT | PK | 账户 id |
| currency | INTEGER | NOT NULL DEFAULT 0 | 货币账本 |
| selected_backpack_offer_id | TEXT | NULL（引用 backpack_offer） | 已选入场背包档位 |
| updated_at | TEXT | NOT NULL DEFAULT now | 更新时间 |

索引：`idx_player_profile_offer (selected_backpack_offer_id)`

#### 3.7 `warehouse_item` —— 仓库物品

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| instance_id | TEXT | PK | 物品实例 id（全局唯一，INV-01） |
| profile_id | TEXT | NOT NULL, FK→player_profile (CASCADE) | 所属账户 |
| definition_id | TEXT | NOT NULL, FK→item_definition | 引用定义 |
| rarity | TEXT | NOT NULL | 稀有度快照 |
| value | INTEGER | NOT NULL DEFAULT 0 | 价值快照 |
| added_at | TEXT | NOT NULL DEFAULT now | 入库时间 |

索引：`idx_warehouse_item_profile (profile_id)`

#### 3.8 `settlement_record` —— 结算记录

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| record_id | TEXT | PK | 记录 id |
| run_id | TEXT | NOT NULL, UNIQUE | 对应局（结算幂等，INV-09） |
| profile_id | TEXT | NOT NULL, FK→player_profile | 账户 |
| result | TEXT | NOT NULL, CHECK(success/failure) | 成功 / 失败 |
| currency_before | INTEGER | NOT NULL | 结算前货币 |
| currency_after | INTEGER | NOT NULL | 结算后货币 |
| carried_item_ids | TEXT | NOT NULL DEFAULT '[]' | JSON：撤离成功带回实例 |
| safe_item_ids | TEXT | NOT NULL DEFAULT '[]' | JSON：失败安全箱实例 |
| settled_at | TEXT | NOT NULL DEFAULT now | 结算时间 |

索引：`idx_settlement_profile (profile_id)`、`idx_settlement_run (run_id)`

#### 3.9 `economy_transaction` —— 经济事务流水（INV-12）

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| transaction_id | TEXT | PK | 事务 id |
| profile_id | TEXT | NOT NULL, FK→player_profile | 账户 |
| type | TEXT | NOT NULL | purchase / sell / settlement / other |
| amount | INTEGER | NOT NULL | 变动金额（±） |
| ref_id | TEXT | NULL | 业务引用（offer_id / 实例 / run_id） |
| balance_before | INTEGER | NOT NULL | 变动前余额 |
| balance_after | INTEGER | NOT NULL | 变动后余额 |
| status | TEXT | NOT NULL DEFAULT 'ok' | 状态 |
| created_at | TEXT | NOT NULL DEFAULT now | 时间 |

索引/约束：
- `idx_transaction_dedupe UNIQUE (profile_id, type, ref_id)` —— 同业务引用防重（INV-12）
- `idx_transaction_profile (profile_id)`

> 表名采用 `economy_transaction` 以避免与 SQLite 保留字 `TRANSACTION` 冲突。

### C. 运行时数据（可选）

#### 3.10 `run_snapshot` —— 每局状态快照（架构 §5 RunState）

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| run_id | TEXT | PK | 局 id |
| phase | TEXT | NOT NULL | 阶段（BOOT/OUT_OF_RUN/.../SETTLED） |
| remaining_match_time | INTEGER | NOT NULL DEFAULT 0 | 剩余总时长 |
| remaining_extraction_time | INTEGER | NOT NULL DEFAULT 0 | 剩余撤离读条 |
| completed_container_count | INTEGER | NOT NULL DEFAULT 0 | 已完成容器数 |
| settled | INTEGER | NOT NULL DEFAULT 0 | 已结算标记（INV-09） |
| carried_item_ids | TEXT | NOT NULL DEFAULT '[]' | JSON |
| safe_item_ids | TEXT | NOT NULL DEFAULT '[]' | JSON |
| updated_at | TEXT | NOT NULL DEFAULT now | 更新时间 |

#### 3.11 `container_state` —— 局内容器状态（架构 §5 ContainerState）

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| container_id | TEXT | PK | 容器 id |
| run_id | TEXT | NOT NULL, FK→run_snapshot (CASCADE) | 所属局 |
| type_id | TEXT | NULL, FK→container_type | 容器类型 |
| reveal_state | TEXT | NOT NULL | UNOPENED/MASKED/REVEALING/PARTIALLY_REVEALED/COMPLETED |
| completed | INTEGER | NOT NULL DEFAULT 0 | 是否完成 |
| counted | INTEGER | NOT NULL DEFAULT 0 | 是否已计数（INV-06 幂等） |

索引：`idx_container_state_run (run_id)`

#### 3.12 `item_instance` —— 局内物品实例（架构 §5 ItemInstance）

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| instance_id | TEXT | PK | 实例 id（唯一，INV-01） |
| run_id | TEXT | NOT NULL, FK→run_snapshot (CASCADE) | 所属局 |
| definition_id | TEXT | NOT NULL, FK→item_definition | 引用定义 |
| rarity | TEXT | NOT NULL | 稀有度 |
| orientation | INTEGER | NOT NULL DEFAULT 0 | 旋转象限 0/1/2/3 |
| location | TEXT | NOT NULL | backpack / safe / dropped / container |
| grid_x | INTEGER | NOT NULL DEFAULT 0 | 格 x |
| grid_y | INTEGER | NOT NULL DEFAULT 0 | 格 y |
| container_id | TEXT | NULL, FK→container_state | 所在容器 |

索引：`idx_item_instance_run (run_id)`、`idx_item_instance_location (run_id, location)`

---

## 4. 迁移与版本

- `schema_migration` 表记录已应用版本（`version` / `applied_at`）。
- `db/migrations/` 下按文件名数字序存放增量脚本；当前为 `001_initial_schema.sql`。
- `DatabaseInitializer` 启动时：建库 → 读取已应用版本 → 依次执行未应用迁移 →
  写入版本。全新数据库等价于执行到最新版本。
- `db/schema.sql` 为当前完整模式的只读参考（等价于全量迁移结果），便于一键
  全新建库与人工审查。

## 5. 与 WORD-27 CSV 的映射

| 数据表 | WORD-27 CSV | 映射说明 |
|---|---|---|
| item_definition | 道具.csv、藏品.csv | definition_id=ID；category 区分道具/藏品；rarity=稀有度；width/height=占格；value=价值；effect_value=效果数值；series=系列 |
| container_type | 撤离点配置.csv | type_id/kind/display_name/grid_width/grid_height 等 |
| backpack_offer | （经济/配置） | offer_id/display_name/price/grid_width/grid_height |
| container_tier_config | （产出权重） | tier / rarity_weights |

> WORD-27 CSV 由测试数据准备任务交付（字段命名与 WORD-23 配置加载兼容）；阶段3
> （WORD-32）将把 CSV 批量导入以上配置表。

## 6. 验收对照（WORD-30）

- [x] 设计文档与建表脚本入库（`docs/database/`、`db/`），可一键初始化（`db/README.md`）
- [x] 仓储接口定义于领域层（`scripts/domain/repositories/`），不暴露数据库实现细节
- [x] 数据库实现位于基础设施层（`scripts/infrastructure/db/`），遵循 WORD-8 分层
- [x] 现有单元测试保持通过（本任务仅新增文件，不改动既有测试路径）
