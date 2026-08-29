## item_data.gd —— FullHaul 物品定义资源（Item & Inventory 域 · Resource 化）
##
## 职责：
##   以 Godot Resource（.tres）承载单件物品的定义数据：字段、元数据与
##   图标/模型等美术资源关联。全部物品 .tres 经 data/items/item_registry.tres
##   （Yard Registry，string_id -> UID）登记，运行期经 ItemResourceCatalog
##   装载，构成物品定义的注册态单一来源（INV-16）。
##
## 设计要点：
##   1. 数据与运行态分离：本类只承载数据；占格/旋转等行为仍由领域模型
##      ItemDefinition 承载（经 ItemDefinition.from_resource 构建）。
##   2. 美术关联（icon/model）为导出资源引用，保存在各物品 .tres 内
##      （ExtResource），资产落盘后填充即生效，引用关系随资源持久保留。
##   3. rarity/category 用枚举保证类型安全，并经 rarity_id()/category_id()
##      映射回既有字符串（GameConfig 揭晓耗时 / 容器产出权重表 / db schema
##      共用），字符串口径不变。
##   4. to_config_dict() 提供与 item_definition 字典字段对齐的兼容视图，
##      供 sqlite 后端与既有字典消费方（编排器占位产出等）过渡使用。

extends Resource
class_name ItemData

## 品质枚举（映射既有 rarity 字符串；数值越高品质越高，红为最高）
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## 类别枚举（物资数据库八大类）
enum Category { COLLECTIBLE, INTEL, ELECTRONICS, TOOL, MEDICAL, FOOD, DAILY, MATERIAL }


## 品质枚举 -> 既有 rarity 字符串（对齐 GameConfig 揭晓耗时表 / 容器权重表）
const RARITY_IDS := {
	Rarity.COMMON: "common",
	Rarity.UNCOMMON: "uncommon",
	Rarity.RARE: "rare",
	Rarity.EPIC: "epic",
	Rarity.LEGENDARY: "legendary",
}

## 品质枚举 -> 中文显示名（源表 rarity 列）
const RARITY_NAMES := {
	Rarity.COMMON: "白",
	Rarity.UNCOMMON: "蓝",
	Rarity.RARE: "紫",
	Rarity.EPIC: "金",
	Rarity.LEGENDARY: "红",
}

## 类别枚举 -> 既有 category 字符串（对齐 db schema category 列）
const CATEGORY_IDS := {
	Category.COLLECTIBLE: "collectible",
	Category.INTEL: "intel",
	Category.ELECTRONICS: "electronics",
	Category.TOOL: "tool",
	Category.MEDICAL: "medical",
	Category.FOOD: "food",
	Category.DAILY: "daily",
	Category.MATERIAL: "material",
}

## 类别枚举 -> 中文显示名（源表 category 列）
const CATEGORY_NAMES := {
	Category.COLLECTIBLE: "收藏品",
	Category.INTEL: "情报文件",
	Category.ELECTRONICS: "电子设备",
	Category.TOOL: "工具",
	Category.MEDICAL: "医疗用品",
	Category.FOOD: "食品",
	Category.DAILY: "生活用品",
	Category.MATERIAL: "物料",
}


## ---- 标识 ----

## 源表 ID（4 位数字，如 "0001"；运行期 definition_id 为 "item_" + item_id）
@export var item_id: String = ""

## 显示名
@export var display_name: String = ""

## 类别
@export var category: Category = Category.MATERIAL

## 品质
@export var rarity: Rarity = Rarity.COMMON


## ---- 数值 ----

## 基础价值（出售/结算用）
@export var base_value: int = 0

## 占格尺寸（宽 x 高，未旋转基础朝向，正整数）
@export var grid_size: Vector2i = Vector2i.ONE

## 最大堆叠数（1 = 不可堆叠）
@export var max_stack: int = 1


## ---- 元数据 ----

## 品质内极值备注（源表 boundary 列，如 "本品质最高；全类别最高"）
@export var boundary_note: String = ""

## 展示描述（扩充字段）
@export var description: String = ""


## ---- 美术关联（资产落盘后填充，经 .tres ExtResource 持久保留）----

## 图标贴图
@export var icon: Texture2D

## 3D 模型（.obj 导入为 Mesh 资源后关联）
@export var model: Mesh


## 运行期定义 ID（与既有 item_definition 字典/DB 主键口径一致）。
func definition_id() -> String:
	return "item_" + item_id


## 品质字符串（对齐既有 rarity 口径；未知值回退 common）。
func rarity_id() -> String:
	return RARITY_IDS.get(rarity, "common")


## 类别字符串（对齐 db schema category 口径）。
func category_id() -> String:
	return CATEGORY_IDS.get(category, "material")


## 类别中文显示名。
func category_name() -> String:
	return CATEGORY_NAMES.get(category, "")


## 未旋转的基础占格尺寸。
func size() -> Vector2i:
	return grid_size


## 数据合法性校验；返回错误信息列表，空数组表示通过。
func validate() -> Array:
	var errors: Array = []
	if item_id.is_empty():
		errors.append("item_id 不能为空")
	if display_name.is_empty():
		errors.append("display_name 不能为空")
	if grid_size.x <= 0 or grid_size.y <= 0:
		errors.append("grid_size 必须为正整数（%s）" % str(grid_size))
	if base_value < 0:
		errors.append("base_value 不能为负（%s）" % display_name)
	if max_stack < 1:
		errors.append("max_stack 必须 >= 1（%s）" % display_name)
	if not RARITY_IDS.has(rarity):
		errors.append("未知品质（%s）" % display_name)
	if not CATEGORY_IDS.has(category):
		errors.append("未知类别（%s）" % display_name)
	return errors


## 兼容视图：输出与 item_definition 字典字段对齐的 Dictionary，
## 供 ItemDefinition.from_config / sqlite 后端 / 编排器等既有字典消费方使用。
func to_config_dict() -> Dictionary:
	return {
		"definition_id": definition_id(),
		"category": category_id(),
		"name": display_name,
		"rarity": rarity_id(),
		"width": grid_size.x,
		"height": grid_size.y,
		"value": base_value,
		"stackable": max_stack > 1,
		"max_stack": max_stack,
		"boundary_note": boundary_note,
		"description": description,
		"color_semantic": rarity_id(),
	}
