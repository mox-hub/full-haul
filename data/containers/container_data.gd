## container_data.gd —— FullHaul 容器定义资源（Loot / Container 域 · Resource 化）
##
## 职责：
##   以 Godot Resource（.tres）承载单个容器/撤离点的定义数据：自身属性
##   （类型、档位、格子尺寸、地图可用性）+ 物品概率系统绑定（品质/类型
##   权重表）+ 图标/模型美术关联。全部容器 .tres 经
##   data/containers/container_registry.tres（Yard Registry）登记，运行期
##   经 ContainerResourceCatalog 装载（INV-16 单一来源）。
##
## 设计要点：
##   1. 概率绑定：rarity_weights / category_weights 直接绑定物品概率系统
##      （ItemProbabilitySystem）的权重表；为空表示回退共享 tier 权重表
##      （container_tier_config）——显式绑定优先，空表继承，逐容器可调。
##   2. 撤离点是特殊容器（kind=extract，INV-15），不参与产出概率。
##   3. to_config_dict() 提供与 container_type 表字段对齐的兼容视图。

extends Resource
class_name ContainerData

## 容器种类：普通容器 | 撤离点（特殊容器）
enum Kind { CONTAINER, EXTRACT }


## Kind -> 既有 kind 字符串（对齐 db schema kind 列）
const KIND_IDS := {
	Kind.CONTAINER: "container",
	Kind.EXTRACT: "extract",
}


## ---- 自身属性 ----

## 容器类型 ID（如 "crate_wood"；运行期即注册表 string_id）
@export var container_id: String = ""

## 显示名
@export var display_name: String = ""

## 种类（普通容器 / 撤离点）
@export var kind: Kind = Kind.CONTAINER

## 产出档位（C1..C5；空表继承共享权重表时的键）
@export var tier: String = "C1"

## 容器内部格子尺寸（宽 x 高）
@export var grid_size: Vector2i = Vector2i(3, 3)

## 地图可用性（预留，对齐 container_type.map_availability）
@export var map_availability: String = ""


## ---- 物品概率系统绑定（ItemProbabilitySystem 权重表）----

## 品质权重表 {rarity 字符串 -> 权重}；空表 = 继承共享 tier 权重表
@export var rarity_weights: Dictionary = {}

## 类型权重表 {category 字符串 -> 权重}；空表 = 类型维度不分层
@export var category_weights: Dictionary = {}


## ---- 美术关联 ----

## 图标贴图
@export var icon: Texture2D

## 3D 模型
@export var model: Mesh

## 模型缩放比例（1.0 = 原始尺寸）
@export var model_scale: float = 1.0


## 种类字符串（对齐 db schema kind 口径）。
func kind_id() -> String:
	return KIND_IDS.get(kind, "container")


## 是否为可产出物品的普通容器（撤离点除外）。
func is_loot_container() -> bool:
	return kind == Kind.CONTAINER


## 数据合法性校验；返回错误信息列表，空数组表示通过。
func validate() -> Array:
	var errors: Array = []
	if container_id.is_empty():
		errors.append("container_id 不能为空")
	if display_name.is_empty():
		errors.append("display_name 不能为空")
	if not KIND_IDS.has(kind):
		errors.append("未知种类（%s）" % display_name)
	if grid_size.x <= 0 or grid_size.y <= 0:
		errors.append("grid_size 必须为正整数（%s）" % display_name)
	if model_scale <= 0.0:
		errors.append("model_scale 必须为正（%s）" % display_name)
	return errors


## 兼容视图：输出与 container_type 表字段对齐的 Dictionary，
## 供 load_container_types 既有字典消费方使用。
func to_config_dict() -> Dictionary:
	return {
		"type_id": container_id,
		"kind": kind_id(),
		"display_name": display_name,
		"tier": tier,
		"grid_width": grid_size.x,
		"grid_height": grid_size.y,
		"icon_id": "",
		"map_availability": map_availability,
	}
