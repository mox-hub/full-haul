## in_memory_data_store.gd —— FullHaul 内存版数据存储（基础设施层）
##
## WORD-31 阶段2：为仓储接口提供「内存后端」的共享数据源，与 SQLite 后端
## 并存，经配置切换（fullhaul/db/backend = memory | sqlite）。
##
## 设计要点：
##   - 以字典模拟「表」：配置数据 / 存档数据 / 运行时数据三类划分与
##     db/schema.sql 对齐（WORD-30）。
##   - 同一实例可被多个仓储对象共享，用于模拟「同一运行周期内的重开读回」
##     （V0.1 持久化范围 = 同一应用运行周期内，TBD-12）。
##   - 本类仅承载数据，不承载任何业务逻辑；领域层/表现层不感知本类。

extends RefCounted
class_name InMemoryDataStore


## ---- 配置数据（静态；对齐 item_definition/container_type/backpack_offer/container_tier_config）----
var item_definitions: Dictionary = {}
var container_types: Dictionary = {}
var backpack_offers: Dictionary = {}
var container_tier_weights: Dictionary = {}

## ---- 存档数据（对齐 player_profile/warehouse_item/settlement_record/economy_transaction）----
## 局外账户（默认本地账户）
var profile: PlayerProfile = null
## run_id -> 结算记录（对齐 settlement_record，run_id 唯一，INV-09）
var settlements: Dictionary = {}
## 经济事务流水（对齐 economy_transaction，防重 INV-12）
var transactions: Array = []

## ---- 运行时数据（对齐 run_snapshot；一局一实例）----
## run_id -> RunState
var run_snapshots: Dictionary = {}


## 取默认本地账户；不存在时创建初始账户。
func ensure_profile() -> PlayerProfile:
	if profile == null:
		profile = PlayerProfile.new()
	return profile