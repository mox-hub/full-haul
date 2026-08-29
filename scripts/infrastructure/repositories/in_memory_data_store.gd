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


## 种子化 V0.1 默认配置数据（切片 9：让内存后端可直接跑通功能链闭环）。
## 单一来源 INV-16：item_definition / container_type / backpack_offer /
## container_tier_config 四张配置表的最小语义种子（对齐 db/schema.sql 字段）。
## 已在组合根装配时调用一次；仅当各表为空时才写入，不覆盖已注入的数据。
func seed_v01_defaults() -> void:
	if item_definitions.is_empty():
		item_definitions = {
			"item_battery": {"definition_id": "item_battery", "category": "item",
				"name": "电池", "rarity": "common", "width": 1, "height": 1,
				"value": 40, "color_semantic": "gray"},
			"item_medkit": {"definition_id": "item_medkit", "category": "item",
				"name": "医疗包", "rarity": "uncommon", "width": 2, "height": 1,
				"value": 120, "color_semantic": "red"},
			"item_techchip": {"definition_id": "item_techchip", "category": "collectible",
				"name": "科技芯片", "rarity": "rare", "width": 1, "height": 1,
				"value": 300, "color_semantic": "blue"},
			"item_scifi_pistol": {"definition_id": "item_scifi_pistol", "category": "item",
				"name": "科幻手枪", "rarity": "rare", "width": 2, "height": 1,
				"value": 350, "color_semantic": "gray"},
			"item_goldenidol": {"definition_id": "item_goldenidol", "category": "collectible",
				"name": "金像", "rarity": "epic", "width": 2, "height": 2,
				"value": 900, "color_semantic": "gold"},
			"item_waterbottle": {"definition_id": "item_waterbottle", "category": "item",
				"name": "净水壶", "rarity": "uncommon", "width": 1, "height": 2,
				"value": 90, "color_semantic": "cyan"},
			"item_rifle": {"definition_id": "item_rifle", "category": "item",
				"name": "突击步枪", "rarity": "rare", "width": 2, "height": 3,
				"value": 600, "color_semantic": "gray"},
			"item_ammobox": {"definition_id": "item_ammobox", "category": "item",
				"name": "重型弹药箱", "rarity": "epic", "width": 3, "height": 3,
				"value": 1100, "color_semantic": "red"},
		}
	if container_types.is_empty():
		container_types = {
			"crate_wood": {"type_id": "crate_wood", "kind": "container",
				"display_name": "木箱", "tier": "C1", "grid_width": 3, "grid_height": 3,
				"icon_id": "", "map_availability": ""},
			"crate_metal": {"type_id": "crate_metal", "kind": "container",
				"display_name": "铁箱", "tier": "C3", "grid_width": 4, "grid_height": 4,
				"icon_id": "", "map_availability": ""},
			"extract_heli": {"type_id": "extract_heli", "kind": "extract",
				"display_name": "撤离点", "tier": "C1", "grid_width": 2, "grid_height": 2,
				"icon_id": "", "map_availability": ""},
		}
	if backpack_offers.is_empty():
		backpack_offers = {
			"backpack_4x4": {"offer_id": "backpack_4x4", "display_name": "4x4 背包",
				"price": 1000, "grid_width": 4, "grid_height": 4},
			"backpack_5x5": {"offer_id": "backpack_5x5", "display_name": "5x5 背包",
				"price": 2500, "grid_width": 5, "grid_height": 5},
			"backpack_6x6": {"offer_id": "backpack_6x6", "display_name": "6x6 背包",
				"price": 5000, "grid_width": 6, "grid_height": 6},
		}
	if container_tier_weights.is_empty():
		container_tier_weights = {
			"C1": {"common": 60, "uncommon": 25, "rare": 10, "epic": 4, "legendary": 1},
			"C2": {"common": 45, "uncommon": 30, "rare": 18, "epic": 6, "legendary": 1},
			"C3": {"common": 30, "uncommon": 35, "rare": 25, "epic": 9, "legendary": 1},
			"C4": {"common": 15, "uncommon": 30, "rare": 35, "epic": 18, "legendary": 2},
			"C5": {"common": 5, "uncommon": 20, "rare": 40, "epic": 30, "legendary": 5},
		}