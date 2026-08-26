## item_instance.gd —— FullHaul 物品实例模型（Item & Inventory 域）
##
## 职责：
##   承载一件物品的「实例」运行态（架构 §5 ItemInstance 实体）：
##   instanceId 唯一；同一时刻恰好位于一个合法位置，或被明确标记为已丢弃
##   （INV-01 唯一归属）。
##
## 字段对齐 db/schema.sql item_instance：instance_id / definition_id /
## orientation（旋转象限 0/1/2/3）/ location（backpack/safe/dropped/container）/
## grid_x / grid_y。

extends RefCounted
class_name ItemInstance

## 实例所处位置类型（对齐 schema location 列；INV-04 背包/安全箱语义分离）
enum Location {
	NONE,       # 未放置（初始）
	BACKPACK,   # 本局背包
	SAFE,       # 安全箱
	CONTAINER,  # 容器内（Loot 域，切片 6 使用）
	DROPPED,    # 已丢弃（INV-01 明确标记）
}


var instance_id: String = ""
var definition_id: String = ""
## 旋转象限 0/1/2/3（每次旋转 +1，对齐 schema orientation）
var orientation: int = 0
var location: Location = Location.NONE
var grid_x: int = -1
var grid_y: int = -1


func _init(p_instance_id := "", p_definition_id := "") -> void:
	instance_id = p_instance_id
	definition_id = p_definition_id


## 当前顶左格坐标；未放置时为 (-1, -1)。
func position() -> Vector2i:
	return Vector2i(grid_x, grid_y)


## 是否已放置在某个格子上（INV-01 唯一归属判定）。
func is_placed() -> bool:
	return location == Location.BACKPACK or location == Location.SAFE \
		or location == Location.CONTAINER