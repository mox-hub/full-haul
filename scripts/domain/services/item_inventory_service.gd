## item_inventory_service.gd —— FullHaul 领域服务：Item & Inventory（物品与背包）域
##
## 职责：
##   实现 IItemInventoryService 契约（架构 §1.1 Item & Inventory 域、§5
##   ItemDefinition/ItemInstance/GridInventory 实体、规范 AC-07/AC-08、
##   INV-01~05，切片 5）：
##   - 物品定义：从 IConfigDataRepository 加载（数据驱动配置单一来源 INV-16）
##   - 物品实例：instanceId 唯一注册（INV-01 唯一归属）
##   - 背包/安全箱两个独立格子（INV-04 语义分离）
##   - 放置校验（占位/边界/合法性）与移动/旋转/丢弃（原子格子操作）
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 领域事件（ITEM_PLACED/ITEM_MOVED/ITEM_ROTATED/ITEM_DROPPED）经注入的
##      IEventBus 发布，供表现层/遥测订阅（架构 §2.3）。
##   3. 一局一实例：背包/安全箱两格为每局状态，经接口注入承载；禁止全局
##      静态单例承载运行态（审核 P1-3）。

extends IItemInventoryService
class_name ItemInventoryService
## 本类继承领域接口 IItemInventoryService（本文件为切片 5 的落地实现）。

## 注入的配置数据仓储（物品定义单一来源 INV-16；鸭子类型，与既有仓储
## 实现一致——实现类 extends RefCounted，不显式 implements 接口）
var _config_repo = null
## 注入的事件总线（格子操作事件发布）
var _bus: IEventBus = null
## definition_id -> ItemDefinition（数据驱动配置缓存）
var _definitions: Dictionary = {}
## instance_id -> ItemInstance（本服务承载的实例注册表）
var _instances: Dictionary = {}
## GridInventory.OwnerType -> GridInventory（背包/安全箱两格）
var _grids: Dictionary = {}


func _init(config_repo, bus: IEventBus) -> void:
	_config_repo = config_repo
	_bus = bus
	_load_definitions()


## 从配置仓储加载物品定义（INV-16 单一来源；非法定义跳过）。
## 优先 Resource 化数据源（load_item_data -> ItemData.tres 注册态）；
## 不可用时回退字典配置（sqlite 行 / 测试桩，from_config）。
func _load_definitions() -> void:
	if _config_repo == null:
		return
	if _config_repo.has_method("load_item_data"):
		var data_dict: Dictionary = _config_repo.load_item_data()
		if not data_dict.is_empty():
			for key in data_dict:
				var def := ItemDefinition.from_resource(data_dict[key])
				if def != null:
					_definitions[def.definition_id] = def
			return
	var raw: Dictionary = _config_repo.load_item_definitions()
	for key in raw:
		var def := ItemDefinition.from_config(raw[key])
		if def != null:
			_definitions[def.definition_id] = def


## 创建物品实例（定义必须存在，INV-16；instanceId 唯一，INV-01）。
func create_item(instance_id: String, definition_id: String) -> ItemInstance:
	if _instances.has(instance_id):
		return null
	if not _definitions.has(definition_id):
		return null
	var item := ItemInstance.new(instance_id, definition_id)
	_instances[instance_id] = item
	return item


## 查询物品实例；不存在返回 null。
func get_item(instance_id: String) -> ItemInstance:
	return _instances.get(instance_id, null)


## 查询物品定义；不存在返回 null。
func get_definition(definition_id: String) -> ItemDefinition:
	return _definitions.get(definition_id, null)


## 查询指定归属类型的格子；未初始化返回 null。
func get_grid(owner: GridInventory.OwnerType) -> GridInventory:
	return _grids.get(owner, null)


## 建立本局背包格子（尺寸来自 Loadout 选定档位；AC-03 前置绑定）。
func setup_backpack(grid_width: int, grid_height: int) -> bool:
	return _setup_grid(GridInventory.OwnerType.BACKPACK, "backpack", grid_width, grid_height)


## 建立安全箱格子（尺寸来自配置 SafeContainerConfig，INV-16）。
func setup_safe(grid_width: int, grid_height: int) -> bool:
	return _setup_grid(GridInventory.OwnerType.SAFE, "safe", grid_width, grid_height)


## 建立仓库格子（局外储物空间；位置为运行时状态，跨重启按入库顺序重排）。
func setup_warehouse(grid_width: int, grid_height: int) -> bool:
	return _setup_grid(GridInventory.OwnerType.WAREHOUSE, "warehouse", grid_width, grid_height)


func _setup_grid(owner: GridInventory.OwnerType, inventory_id: String,
		grid_width: int, grid_height: int) -> bool:
	if grid_width <= 0 or grid_height <= 0:
		return false
	_grids[owner] = GridInventory.new(inventory_id, owner, grid_width, grid_height)
	return true


## 放置校验：物品能否放入指定格子的目标位置（INV-04）。
func can_place(instance_id: String, owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	var item: ItemInstance = _instances.get(instance_id, null)
	var grid: GridInventory = _grids.get(owner, null)
	if item == null or grid == null:
		return false
	return grid.can_place(_current_size(item), to)


## 放置物品到指定格子的目标位置（INV-01 唯一归属；失败保持操作前状态）。
func place_item(instance_id: String, owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	var item: ItemInstance = _instances.get(instance_id, null)
	if item == null:
		return false
	## INV-01：同一实例同一时刻只属一个位置；已放置/已丢弃不可重复放置
	if item.location != ItemInstance.Location.NONE:
		return false
	var grid: GridInventory = _grids.get(owner, null)
	if grid == null:
		return false
	var size: Vector2i = _current_size(item)
	if not grid.place(instance_id, size, to):
		return false
	item.location = _location_from_owner(owner)
	item.grid_x = to.x
	item.grid_y = to.y
	_publish(DomainEvents.Events.ITEM_PLACED, instance_id, Vector2i(-1, -1), to)
	return true


## 移动物品到目标格子的目标位置（可跨格子，AC-08）。
func move_item(instance_id: String, to_owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	var item: ItemInstance = _instances.get(instance_id, null)
	if item == null:
		return false
	if not item.is_placed():
		return false
	var from: Vector2i = item.position()
	var from_owner: GridInventory.OwnerType = _owner_from_location(item.location)
	var src_grid: GridInventory = _grids.get(from_owner, null)
	var dst_grid: GridInventory = _grids.get(to_owner, null)
	if src_grid == null or dst_grid == null:
		return false
	if from_owner == to_owner:
		## 同格内移动（INV-04 校验，失败保持原状）
		if not src_grid.move(instance_id, to):
			return false
	else:
		## 跨格移动：先校验目标格（INV-04），原子执行（INV-01/02/03）
		var size: Vector2i = _current_size(item)
		if not dst_grid.can_place(size, to):
			return false
		if not src_grid.remove(instance_id):
			return false
		if not dst_grid.place(instance_id, size, to):
			## 回滚：目标放置失败时还原源格（INV-03 无误失）
			src_grid.place(instance_id, _current_size(item), from)
			return false
	item.location = _location_from_owner(to_owner)
	item.grid_x = to.x
	item.grid_y = to.y
	_publish(DomainEvents.Events.ITEM_MOVED, instance_id, from, to)
	return true


## 旋转物品（更新朝向；旋转后占格一致 INV-05）。非法旋转（越界/重叠）时
## 保持原朝向（AC-07 非法旋转 / INV-04）。
func rotate_item(instance_id: String) -> bool:
	var item: ItemInstance = _instances.get(instance_id, null)
	if item == null:
		return false
	if not item.is_placed():
		return false
	var owner: GridInventory.OwnerType = _owner_from_location(item.location)
	var grid: GridInventory = _grids.get(owner, null)
	if grid == null:
		return false
	var new_orientation: int = (item.orientation + 1) % 4
	var new_size: Vector2i = _size_for_orientation(item.definition_id, new_orientation)
	if new_size == Vector2i.ZERO:
		return false
	if not grid.update_size(instance_id, new_size):
		return false
	item.orientation = new_orientation
	var at: Vector2i = item.position()
	_publish(DomainEvents.Events.ITEM_ROTATED, instance_id, at, at)
	return true


## 丢弃物品（INV-01/03：移出格子并明确标记为已丢弃）。
func drop_item(instance_id: String) -> bool:
	var item: ItemInstance = _instances.get(instance_id, null)
	if item == null:
		return false
	if item.location == ItemInstance.Location.DROPPED:
		return false
	var from: Vector2i = item.position()
	var owner: GridInventory.OwnerType = _owner_from_location(item.location)
	var grid: GridInventory = _grids.get(owner, null)
	if grid != null:
		grid.remove(instance_id)
	item.location = ItemInstance.Location.DROPPED
	item.grid_x = -1
	item.grid_y = -1
	_publish(DomainEvents.Events.ITEM_DROPPED, instance_id, from, Vector2i(-1, -1))
	return true


## 当前朝向下的占格尺寸（INV-05）。
func _current_size(item: ItemInstance) -> Vector2i:
	return _size_for_orientation(item.definition_id, item.orientation)


func _size_for_orientation(definition_id: String, orientation: int) -> Vector2i:
	var def: ItemDefinition = _definitions.get(definition_id, null)
	if def == null:
		return Vector2i.ZERO
	return def.rotated_size(orientation)


func _owner_from_location(location: ItemInstance.Location) -> GridInventory.OwnerType:
	match location:
		ItemInstance.Location.SAFE:
			return GridInventory.OwnerType.SAFE
		ItemInstance.Location.WAREHOUSE:
			return GridInventory.OwnerType.WAREHOUSE
		_:
			return GridInventory.OwnerType.BACKPACK


func _location_from_owner(owner: GridInventory.OwnerType) -> ItemInstance.Location:
	match owner:
		GridInventory.OwnerType.SAFE:
			return ItemInstance.Location.SAFE
		GridInventory.OwnerType.WAREHOUSE:
			return ItemInstance.Location.WAREHOUSE
		_:
			return ItemInstance.Location.BACKPACK


## 发布格子操作事件（payload 为 GridOpData 数据对象，架构 §2.3）。
func _publish(event_id: int, instance_id: String, from: Vector2i, to: Vector2i) -> void:
	if _bus != null:
		_bus.publish(event_id, DomainEvents.GridOpData.new(instance_id, from, to))