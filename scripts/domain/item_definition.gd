## item_definition.gd —— FullHaul 物品定义模型（Item & Inventory 域）
##
## 职责：
##   承载物品的「定义」数据（架构 §5 ItemDefinition 实体）：定义与实例分离。
##   定义来自数据驱动配置单一来源（INV-16），本类为纯数据 + 尺寸计算。
##
## 设计要点：
##   - 纯逻辑：extends RefCounted，零 Godot 节点依赖，可独立单元测试
##     （架构原则 2）。
##   - 尺寸为正整数（架构 §5 约束）；旋转后占格由 orientation 计算
##     （INV-05 形状一致）。

extends RefCounted
class_name ItemDefinition

var definition_id: String = ""
var name: String = ""
var rarity: String = ""
var width: int = 0
var height: int = 0
var value: int = 0
var color_semantic: String = ""


func _init(p_definition_id := "", p_name := "", p_rarity := "",
		p_width := 0, p_height := 0, p_value := 0, p_color_semantic := "") -> void:
	definition_id = p_definition_id
	name = p_name
	rarity = p_rarity
	width = p_width
	height = p_height
	value = p_value
	color_semantic = p_color_semantic


## 未旋转的基础占格尺寸。
func size() -> Vector2i:
	return Vector2i(width, height)


## 指定朝向（0..3，90° 步进）下的占格尺寸（INV-05）。
## 奇数次旋转（90°/270°）交换宽高。
func rotated_size(orientation: int) -> Vector2i:
	if orientation % 2 == 1:
		return Vector2i(height, width)
	return Vector2i(width, height)


## 定义是否合法（尺寸为正整数，架构 §5 约束）。
func is_valid() -> bool:
	return width > 0 and height > 0


## 从数据驱动配置字典构建定义；字段与 item_definition 配置表对齐（INV-16）。
## 尺寸非法（非正整数）或缺少必要字段时返回 null。
static func from_config(data: Dictionary) -> ItemDefinition:
	if not data.has("definition_id") or not data.has("width") or not data.has("height"):
		return null
	var def := ItemDefinition.new(
		str(data.get("definition_id", "")),
		str(data.get("name", "")),
		str(data.get("rarity", "")),
		int(data.get("width", 0)),
		int(data.get("height", 0)),
		int(data.get("value", 0)),
		str(data.get("color_semantic", "")))
	return def if def.is_valid() else null