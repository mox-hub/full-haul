# FullHaul 切片 9 强制功能链闭环验证记录

> 交付物：本文件为《满载而归（FullHaul）》V0.1 切片 9（WORD-39）「Telemetry + 表现层接场景/UI，跑通强制功能链闭环」的验证记录。
>
> 工程：mox-hub/full-haul（Godot 4.7，GdUnit4）。验证方式：无头（headless）黑盒驱动工程主场景，逐环节断言领域状态与界面切换。

## 1. 验证场景（对应强制功能链）

| 环节 | 实现入口 | 验收映射 |
|---|---|---|
| 进入一局 | 局外「开始一局」→ 入场装载「确认入场（购买背包）」 | AC-02 / AC-21 |
| 搜刮 | 局内「搜索容器（携带产出）」（Loot 域） | AC-04/05/06/17/18 |
| 携带 | 揭晓产出携带入背包格子（Item 域） | AC-07/08、INV-01/04 |
| 撤离 | 完成 5 容器解锁 → 开始撤离（读条/总计时） | AC-09/10/11、INV-07/08 |
| 结算入库 | 成功结算后携带物品入库仓库（Settlement/Warehouse） | AC-12/13、INV-09/10 |
| 出售 | 局外仓库出售物品，货币入账（Transaction 原子性） | AC-14/15、INV-12 |
| 遥测 | 各域关键事件经 TelemetryService 逐条留痕 | 规范 6.4、架构 §2.3 |

## 2. 验证方法与命令

```bash
# 无头运行聚合测试运行器（含切片 9 新增套件）
godot --headless --path . res://tests/test_runner.tscn

# 单独运行强制功能链闭环集成套件
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
     -a res://tests/integration/test_full_chain_loop.gd --ignoreHeadlessMode
```

## 3. 验证结果

### 3.1 强制功能链闭环（test_full_chain_loop.gd）

逐环节断言结果（本次本地无头运行）：

- ✅ 启动进入局外，初始货币 100000（AC-21）
- ✅ 进入一局并购买 5x5 背包：货币 100000 → 97500（INV-12 扣款）
- ✅ 搜刮 + 携带：搜索 5 个容器，`carried_item_count() == 5`，撤离解锁（INV-07）
- ✅ 撤离成功：EXTRACTING → RUN_SUCCEEDED，携带物品快照（INV-10）
- ✅ 结算入库：`warehouse_item_ids.size() == 5`（INV-09/10）
- ✅ 出售：`sell_warehouse_item` 成交价 ≥ 1，货币 + 成交价（INV-12 守恒）
- ✅ 遥测留痕：RUN_INITIALIZED / BACKPACK_PURCHASED / CONTAINER_COMPLETED×5 /
  EXTRACT_UNLOCKED / EXTRACT_STARTED / RUN_SUCCEEDED / RUN_SETTLED /
  WAREHOUSE_ITEM_ADDED×5 / ITEM_SOLD 均逐条记录（规范 6.4，不构成产品规则来源）

### 3.2 全量测试（test_runner.tscn）

- 结果：**186 passed / 0 failed**
- 新增套件：
  - `test_telemetry_service`（领域：订阅全事件、留痕、不退订语义、不改领域数据）
  - `test_telemetry_wiring`（编排器接线：携带入背包、搜索携带、完整成功闭环、回退占位）
  - `test_full_chain_loop`（集成：强制功能链端到端闭环 + 遥测验证）
  - `test_repository_provider`（内存后端种子化 V0.1 配置数据，INV-16 单一来源）

## 4. 覆盖说明

- Telemetry 域订阅全部领域事件（架构 §1.1 Config & Telemetry、§2.3），只埋点不改状态。
- 表现层接线：局外（货币/仓库/出售）、入场装载（背包档位购买）、局内（真实搜索+携带+
  真实双计时）、结算（入库提示）、HUD（剩余时间/携带数/撤离读条）。
- 多局复用：已购背包不重复扣款（事务防重 INV-12），保证「再开局」闭环。
- 未覆盖/占位：容器内揭晓顺序（TBD-03）、搜索中断恢复（TBD-02）、同刻计时优先级
  （TBD-04）为规范未决项，本次不补默认值；真实逐件揭晓动画为表现层后续打磨项。

## 5. 验收结论

强制功能链「进入一局 → 搜刮 → 携带 → 撤离 → 结算入库 → 出售/购买」闭环已在 Godot 无头
环境黑盒可操作验证通过；遥测埋点随链逐事件留痕。请 Haoran Li 审核。