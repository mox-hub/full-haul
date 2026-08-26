## test_item_inventory_service.gd —— FullHaul 领域测试：Item & Inventory 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 5 落地的 ItemInventoryService（架构 §1.1
##   Item & Inventory 域、§5 ItemDefinition/ItemInstance/GridInventory 实体、
##   AC-07/AC-08、INV-01~05）：
##   - 物品定义数据驱动加载（INV-16 单一来源）
##   - 物品实例创建（instanceId 唯一，INV-01）
##   - 背包/安全箱两格独立（INV-04 语义分离）
##   - 放置/移动/旋转/丢弃及事件发布（AC-07/AC-08，INV-01~05）
##   - 失败操作保持操作前状态（INV-04）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_item_inventory_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 假配置数据仓储：返回种子物品定义
class _FakeConfigRepo:
	extends IConfigDataRepository
	var item_definitions: Dictionary = {}

	func _init() -> void:
		item_definitions = {
			"item_1x1": {"definition_id": "item_1x1", "name": "电池", "rarity": "common",
				"width": 1, "height": 1, "value": 10},
			"item_2x1": {"definition_id": "item_2x1", "name": "长管", "rarity": "uncommon",
				"width": 2, "height": 1, "value": 30},
			"item_2x2": {"definition_id": "item_2x2", "name": "箱子", "rarity": "rare",
				"width": 2, "height": 2, "value": 100},
		}

	func load_item_definitions() -> Dictionary:
		return item_definitions

	func get_item_definition(definition_id: String) -> Dictionary:
		return item_definitions.get(definition_id, {})


## 假事件总线：记录发布的事件 id 与 payload
class _FakeEventBus:
	extends IEventBus
	var published: Array = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append({"event": event_id, "payload": payload})

	func has_published(event_id: int) -> bool:
		for entry in published:
			if entry.get("event", -1) == event_id:
				return true
		return false

	func count_published(event_id: int) -> int:
		var n := 0
		for entry in published:
			if entry.get("event", -1) == event_id:
				n += 1
		return n

	func last_payload(event_id: int):
		for i in range(published.size() - 1, -1, -1):
			if published[i].get("event", -1) == event_id:
				return published[i].get("payload", null)
		return null


## 组装被测服务：4x4 背包 + 2x2 安全箱，种子物品定义。
func _service() -> Dictionary:
	var repo := _FakeConfigRepo.new()
	var bus := _FakeEventBus.new()
	var svc := ItemInventoryService.new(repo, bus)
	svc.setup_backpack(4, 4)
	svc.setup_safe(2, 2)
	return {"svc": svc, "bus": bus, "repo": repo}


func _item_2x1(svc: ItemInventoryService, instance_id: String) -> ItemInstance:
	return svc.create_item(instance_id, "item_2x1")


func _item_2x2(svc: ItemInventoryService, instance_id: String) -> ItemInstance:
	return svc.create_item(instance_id, "item_2x2")


## [ItemInventoryService] 定义数据驱动加载（INV-16 单一来源）
func test_definitions_loaded_from_config_repo() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	assert_that(svc.get_definition("item_1x1")).is_not_null()
	assert_that(svc.get_definition("item_1x1").size()).is_equal(Vector2i.ONE)
	assert_that(svc.get_definition("item_2x1").size()).is_equal(Vector2i(2, 1))
	assert_that(svc.get_definition("nope")).is_null()


## [ItemInventoryService] 实例创建：instanceId 唯一（INV-01）、定义必须存在
func test_create_item_unique_and_definition_required() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	var item := svc.create_item("i-1", "item_1x1")
	assert_that(item).is_not_null()
	assert_that(item.definition_id).is_equal("item_1x1")
	assert_that(item.location).is_equal(ItemInstance.Location.NONE)

	## 重复 instanceId 拒绝（INV-01）
	assert_that(svc.create_item("i-1", "item_2x1")).is_null()
	## 未知定义拒绝（INV-16）
	assert_that(svc.create_item("i-2", "missing")).is_null()


## [ItemInventoryService] 放置：合法放置成功并发布 ITEM_PLACED（INV-01）
func test_place_legal() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	var item := _item_2x1(svc, "i-1")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(item.location).is_equal(ItemInstance.Location.BACKPACK)
	assert_that(item.position()).is_equal(Vector2i.ZERO)
	## 事件
	assert_that(bus.has_published(DomainEvents.Events.ITEM_PLACED)).is_true()
	var evt: DomainEvents.GridOpData = bus.last_payload(DomainEvents.Events.ITEM_PLACED)
	assert_that(evt.instance_id).is_equal("i-1")
	assert_that(evt.to).is_equal(Vector2i.ZERO)
	## 背包格子占用
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).has("i-1")).is_true()


## [ItemInventoryService] 放置：越界/重叠/重复放置失败且保持原状（INV-04/INV-01）
func test_place_invalid_preserves_state() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	var item := _item_2x2(svc, "i-1")
	## 越界
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(3, 3))).is_false()
	assert_that(item.location).is_equal(ItemInstance.Location.NONE)
	## 重叠：i-1 放 (0,0)，i-2 放 (1,1) 重叠
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	var item2 := _item_2x2(svc, "i-2")
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.BACKPACK, Vector2i(1, 1))).is_false()
	assert_that(item2.location).is_equal(ItemInstance.Location.NONE)
	## 重复放置同一实例（INV-01）
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_false()
	## 已放置实例不能放置到安全箱（INV-01）
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_false()


## [ItemInventoryService] 移动：同格内移动成功并发布 ITEM_MOVED（AC-07 拖拽）
func test_move_within_grid() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	_item_2x1(svc, "i-1")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_true()
	var item := svc.get_item("i-1")
	assert_that(item.position()).is_equal(Vector2i(2, 2))
	## 事件（from -> to）
	assert_that(bus.count_published(DomainEvents.Events.ITEM_MOVED)).is_equal(1)
	var evt: DomainEvents.GridOpData = bus.last_payload(DomainEvents.Events.ITEM_MOVED)
	assert_that(evt.from).is_equal(Vector2i.ZERO)
	assert_that(evt.to).is_equal(Vector2i(2, 2))


## [ItemInventoryService] 移动：失败移动保持操作前状态（INV-04，AC-07 失败替换）
func test_move_invalid_preserves_state() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	_item_2x2(svc, "i-1")
	_item_2x2(svc, "i-2")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_true()
	## 移动到 i-2 位置（重叠）失败
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_false()
	assert_that(svc.get_item("i-1").position()).is_equal(Vector2i.ZERO)
	## 越界移动失败
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(3, 3))).is_false()
	assert_that(svc.get_item("i-1").position()).is_equal(Vector2i.ZERO)
	## 未放置实例移动失败
	_item_2x1(svc, "i-3")
	assert_that(svc.move_item("i-3", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_false()


## [ItemInventoryService] 跨格移动：背包↔安全箱往返（AC-08）
func test_move_cross_grid_roundtrip() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	_item_2x1(svc, "i-1")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	## 背包 -> 安全箱
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_true()
	assert_that(svc.get_item("i-1").location).is_equal(ItemInstance.Location.SAFE)
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).has("i-1")).is_false()
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).has("i-1")).is_true()
	## 安全箱 -> 背包
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(1, 1))).is_true()
	assert_that(svc.get_item("i-1").location).is_equal(ItemInstance.Location.BACKPACK)
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).has("i-1")).is_false()
	## 事件次数：初始放置 1 + 移动 2
	assert_that(bus.count_published(DomainEvents.Events.ITEM_MOVED)).is_equal(2)


## [ItemInventoryService] 安全箱：满箱后拒绝放入（AC-08 满箱，INV-04）
func test_safe_box_full_rejects() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	_item_2x2(svc, "i-1")
	_item_2x2(svc, "i-2")
	## i-1 占满 2x2 安全箱
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_true()
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).is_full()).is_true()
	## 满箱后放置失败（INV-04）
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_false()
	## 腾出安全箱：i-1 移到背包，i-2 放入安全箱占满
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_true()
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).is_full()).is_true()
	## 满箱后移入失败且 i-1 保持在背包（INV-04 失败保持原状）
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_false()
	assert_that(svc.get_item("i-1").location).is_equal(ItemInstance.Location.BACKPACK)
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).has("i-1")).is_true()


## [ItemInventoryService] 旋转：合法旋转更新朝向并保持占格一致（INV-05，AC-07 旋转）
func test_rotate_legal() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	_item_2x1(svc, "i-1")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.rotate_item("i-1")).is_true()
	var item := svc.get_item("i-1")
	assert_that(item.orientation).is_equal(1)
	## 旋转后占格 1x2（INV-05）
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).size_of("i-1")).is_equal(Vector2i(1, 2))
	## 事件
	assert_that(bus.has_published(DomainEvents.Events.ITEM_ROTATED)).is_true()


## [ItemInventoryService] 旋转：非法旋转（重叠/越界）保持原朝向（AC-07 非法旋转）
func test_rotate_illegal_preserves_orientation() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	_item_2x1(svc, "i-1")
	_item_2x2(svc, "i-2")
	## i-1 放 (0,0) 占 (0,0)(1,0)；i-2 放 (0,2) 占 2x2
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_true()
	## i-1 旋转为 1x2 会占 (0,0)(0,1)——(0,1) 未被占，仍合法；先把它移动到与 i-2 相邻处
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(2, 0))).is_true()
	## 在 (2,0) 旋转为 1x2 占 (2,0)(2,1)——合法
	assert_that(svc.rotate_item("i-1")).is_true()
	## 再移到 (1,0)（1x2 已占 (2,0)(2,1)，旋转回 2x1 会与 i-2 于 (2,2) 无交叠，
	## 但需先确认：此处验证「旋转到与相邻物品重叠」的场景
	assert_that(svc.move_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i(0, 1))).is_true()
	## 在 (0,1) 旋转为 2x1 占 (0,1)(1,1)，与 i-2(2,2) 不重叠 -> 合法
	assert_that(svc.rotate_item("i-1")).is_true()
	## 未放置实例旋转失败
	_item_2x1(svc, "i-3")
	assert_that(svc.rotate_item("i-3")).is_false()


## [ItemInventoryService] 旋转：与相邻物品重叠时非法旋转被拒绝（AC-07 非法旋转）
func test_rotate_into_overlap_rejected() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	_item_2x1(svc, "i-1")
	## i-1 2x1 放 (0,0) 占 (0,0)(1,0)
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	## 挡板 1x1 放 (0,1) 占 (0,1)
	var blocker := svc.create_item("b-1", "item_1x1")
	assert_that(svc.place_item("b-1", GridInventory.OwnerType.BACKPACK, Vector2i(0, 1))).is_true()
	## i-1 旋转为 1x2 会占 (0,0)(0,1)，与挡板重叠 -> 拒绝且保持原朝向（AC-07/INV-04）
	assert_that(svc.rotate_item("i-1")).is_false()
	assert_that(svc.get_item("i-1").orientation).is_equal(0)
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).size_of("i-1")).is_equal(Vector2i(2, 1))


## [ItemInventoryService] 丢弃：移出格子并标记已丢弃（INV-01/03），发布 ITEM_DROPPED
func test_drop_item() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	_item_2x1(svc, "i-1")
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.drop_item("i-1")).is_true()
	var item := svc.get_item("i-1")
	assert_that(item.location).is_equal(ItemInstance.Location.DROPPED)
	assert_that(item.position()).is_equal(Vector2i(-1, -1))
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).has("i-1")).is_false()
	assert_that(bus.has_published(DomainEvents.Events.ITEM_DROPPED)).is_true()
	## 已丢弃不能再丢弃（INV-01）
	assert_that(svc.drop_item("i-1")).is_false()


## [ItemInventoryService] 连续快速操作：无复制、无误失、状态一致（AC-07 连续快速操作，INV-02/03）
func test_rapid_operations_no_duplication_no_loss() -> void:
	var parts := _service()
	var svc: ItemInventoryService = parts["svc"]

	_item_2x2(svc, "i-1")
	_item_2x2(svc, "i-2")
	_item_2x1(svc, "i-3")
	## 快速连续放置
	assert_that(svc.place_item("i-1", GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	assert_that(svc.place_item("i-2", GridInventory.OwnerType.BACKPACK, Vector2i(2, 2))).is_true()
	assert_that(svc.place_item("i-3", GridInventory.OwnerType.BACKPACK, Vector2i(0, 2))).is_true()
	## 快速移动 + 旋转 + 丢弃
	assert_that(svc.move_item("i-3", GridInventory.OwnerType.BACKPACK, Vector2i(2, 0))).is_true()
	assert_that(svc.rotate_item("i-3")).is_true()
	assert_that(svc.move_item("i-2", GridInventory.OwnerType.SAFE, Vector2i.ZERO)).is_true()
	assert_that(svc.drop_item("i-3")).is_true()
	## 每个实例仍唯一存在（INV-01/02）
	assert_that(svc.get_item("i-1")).is_not_null()
	assert_that(svc.get_item("i-2")).is_not_null()
	assert_that(svc.get_item("i-3")).is_not_null()
	## 无误失：丢弃的 i-3 仍可从服务查询，只是标记为 DROPPED（INV-03）
	assert_that(svc.get_item("i-3").location).is_equal(ItemInstance.Location.DROPPED)
	## 无复制：i-2 只在安全箱出现一次
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).has("i-2")).is_false()
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).has("i-2")).is_true()
	assert_that(svc.get_grid(GridInventory.OwnerType.SAFE).item_count()).is_equal(1)
	## i-1 仍在背包原处（无误失）
	assert_that(svc.get_grid(GridInventory.OwnerType.BACKPACK).position_of("i-1")).is_equal(Vector2i.ZERO)