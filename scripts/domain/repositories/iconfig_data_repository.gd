## iconfig_data_repository.gd —— FullHaul 配置数据仓储接口（领域层契约）
##
## 读取配置数据（道具/藏品/容器/撤离点/背包档位/产出权重等静态数据）。
## 对齐 WORD-27 CSV 与架构 §5 数据模型；领域层经本接口消费配置，保证配置
## 单一来源（INV-16）。数据库实现位于基础设施层，本接口不暴露任何数据库
## 细节（表名/连接/引擎），仅返回领域类型。

extends RefCounted
class_name IConfigDataRepository


## 道具 / 藏品定义表（definition_id -> Dictionary，字段与 item_definition 对齐）。
## 返回 Dictionary；无记录时返回空 Dictionary。
func load_item_definitions() -> Dictionary:
	return {}


## 物品定义 Resource 表（definition_id -> ItemData，Resource 化数据源）。
## 后端未提供 Resource 化数据时返回空 Dictionary，消费方回退
## load_item_definitions() 字典视图。
func load_item_data() -> Dictionary:
	return {}


## 按 definition_id 读取单个道具/藏品定义；不存在返回空 Dictionary。
func get_item_definition(definition_id: String) -> Dictionary:
	return {}


## 容器 / 撤离点类型表（type_id -> Dictionary）。
func load_container_types() -> Dictionary:
	return {}


## 背包档位表（offer_id -> Dictionary）。
func load_backpack_offers() -> Dictionary:
	return {}


## 容器产出权重表（tier -> {rarity: weight}）。
func load_container_tier_weights() -> Dictionary:
	return {}
