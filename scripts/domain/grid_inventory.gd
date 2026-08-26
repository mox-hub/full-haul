## grid_inventory.gd —— FullHaul 格子背包模型（Item & Inventory 域）
##
## 职责：
##   承载一个「格子」的占用状态与放置校验（架构 §5 GridInventory 实体、
##   INV-04 格子合法）：占位（不重叠）、边界（不越界）、合法性（尺寸为正）。
##   背包/安全箱/仓库语义分离由 owner_type 表达（INV-04）。
##
## 设计要点：
##   - 纯逻辑：extends RefCounted，零 Godot 节点依赖，可独立单元测试
##     （架构原则 2）。
##   - placements 记录 instance_id -> { pos, size }，其中 size 为当前
##     朝向下的占格尺寸；旋转后由服务层经 update_size 保持与实例一致
##     （INV-05 形状一致）。
##   - 失败操作保持操作前状态（INV-04）。

extends RefCounted
class_name GridInventory

## 格子归属类型（INV-04 背包/安全箱/仓库语义分离）
enum OwnerType {
	BACKPACK,   # 本局背包
	SAFE,       # 安全箱
	WAREHOUSE,  # 仓库（局外）
}


var inventory_id: String = ""
var owner_type: OwnerType = OwnerType.BACKPACK
var width: int = 0
var height: int = 0
## instance_id -> { "pos": Vector2i 顶左格坐标, "size": Vector2i 当前占格尺寸 }
var placements: Dictionary = {}


func _init(p_inventory_id := "", p_owner_type := OwnerType.BACKPACK,
		p_width := 0, p_height := 0) -> void:
	inventory_id = p_inventory_id
	owner_type = p_owner_type
	width = p_width
	height = p_height


func has(instance_id: String) -> bool:
	return placements.has(instance_id)


## 某实例当前顶左格坐标；不存在返回 (-1, -1)。
func position_of(instance_id: String) -> Vector2i:
	var entry: Dictionary = placements.get(instance_id, {})
	return entry.get("pos", Vector2i(-1, -1))


## 某实例当前占格尺寸；不存在返回 ZERO。
func size_of(instance_id: String) -> Vector2i:
	var entry: Dictionary = placements.get(instance_id, {})
	return entry.get("size", Vector2i.ZERO)


func item_count() -> int:
	return placements.size()


func is_empty() -> bool:
	return placements.is_empty()


## 已占用的格子数（各物品面积之和）。
func occupied_cells() -> int:
	var total := 0
	for entry in placements.values():
		var s: Vector2i = entry.get("size", Vector2i.ZERO)
		total += s.x * s.y
	return total


## 是否满格（已无空格，AC-07 满包 / AC-08 满箱）。
func is_full() -> bool:
	return occupied_cells() >= width * height


## 放置校验：尺寸为正 + 不越界 + 不重叠（INV-04）。
## ignore_instance_id 用于移动/旋转时忽略自身（同格内操作）。
func can_place(size: Vector2i, at: Vector2i, ignore_instance_id := "") -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	if at.x < 0 or at.y < 0:
		return false
	if at.x + size.x > width or at.y + size.y > height:
		return false
	for iid in placements:
		if iid == ignore_instance_id:
			continue
		var entry: Dictionary = placements[iid]
		if _overlap(at, size, entry.get("pos", Vector2i.ZERO),
				entry.get("size", Vector2i.ZERO)):
			return false
	return true


## 放置：校验通过才记录（INV-04 失败保持操作前状态）。
func place(instance_id: String, size: Vector2i, at: Vector2i) -> bool:
	if placements.has(instance_id):
		return false
	if not can_place(size, at):
		return false
	placements[instance_id] = {"pos": at, "size": size}
	return true


## 移除某实例。
func remove(instance_id: String) -> bool:
	return placements.erase(instance_id)


## 同格内移动（保持当前尺寸；INV-04 校验）。
func move(instance_id: String, at: Vector2i) -> bool:
	if not placements.has(instance_id):
		return false
	var size: Vector2i = size_of(instance_id)
	if not can_place(size, at, instance_id):
		return false
	placements[instance_id]["pos"] = at
	return true


## 更新占格尺寸（旋转后，INV-05 形状一致；校验通过才更新）。
func update_size(instance_id: String, new_size: Vector2i) -> bool:
	if not placements.has(instance_id):
		return false
	var at: Vector2i = position_of(instance_id)
	if not can_place(new_size, at, instance_id):
		return false
	placements[instance_id]["size"] = new_size
	return true


## 两个矩形是否重叠（半开区间）。
static func _overlap(a_at: Vector2i, a_size: Vector2i, b_at: Vector2i, b_size: Vector2i) -> bool:
	return a_at.x < b_at.x + b_size.x and b_at.x < a_at.x + a_size.x \
		and a_at.y < b_at.y + b_size.y and b_at.y < a_at.y + a_size.y