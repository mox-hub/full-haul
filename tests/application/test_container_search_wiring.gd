## test_container_search_wiring.gd —— FullHaul 接线测试：Loot/Container 接入编排器（GdUnit4）
##
## 职责：
##   切片 6：验证 RunFlowOrchestrator 接入 Loot / Container 域后的接线行为：
##   - 编排器暴露 container_search() 访问器（供表现层/后续切片经接口访问）
##   - 局内完成一个容器：完成数经容器搜索域统计（INV-06 幂等）并做撤离
##     解锁阈值判定（INV-07）
##   - 局外调用容器搜索用例不污染领域状态（局外守卫）
##   - 新一局开始清空容器登记（INV-14 多局隔离）
##   - 未注入 ContainerSearchService 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_container_search_wiring.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const EventBusScript := preload("res://autoload/EventBus.gd")

## 本地事件总线适配器：把测试内 EventBus 实例桥接到 IEventBus
class _LocalBusAdapter:
	extends IEventBus

	var _bus: Node = null

	func _init(bus: Node) -> void:
		_bus = bus

	func publish(event_id: int, payload: RefCounted = null) -> void:
		_bus.call("publish", event_id, payload)

	func subscribe(event_id: int, callback: Callable) -> int:
		return _bus.call("subscribe", event_id, callback)

	func unsubscribe(event_id: int, sub_id: int) -> void:
		_bus.call("unsubscribe", event_id, sub_id)


## 内存态局内状态存储
class _InMemoryStateStore:
	extends IRunStateStore

	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state


## 假配置加载器：返回默认 GameConfig
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


var _bus: Node = null
var _received: Array[int] = []


func before_test() -> void:
	_bus = auto_free(EventBusScript.new())
	_bus.call("_ready")
	_received = []
	for event_id in [
		DomainEvents.Events.OUT_OF_RUN_ENTERED,
		DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.Events.EXTRACT_UNLOCKED,
		DomainEvents.Events.EXTRACT_STARTED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


## 组装带 Loot / Container 域的编排器（切片 6）。
func _wired_orchestrator() -> Dictionary:
	var bus := _LocalBusAdapter.new(_bus)
	var store := _InMemoryStateStore.new()
	var run_session := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	var container_search := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	var orch := RunFlowOrchestrator.new(bus, store, _FakeConfigLoader.new(),
		null, null, run_session, null, container_search)
	return {"orch": orch, "container_search": container_search, "store": store}


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 进入一局（OUT_OF_RUN -> LOADOUT -> IN_RUN_LOCKED）。
func _enter_run(orch: RunFlowOrchestrator) -> void:
	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)


## 在局内完整完成一个容器（打开 -> 揭晓 -> 完成）。
func _complete_one(orch: RunFlowOrchestrator, container_id: String, instance_id: String) -> void:
	assert_that(orch.open_container(container_id, 1, [instance_id])).is_true()
	assert_that(orch.start_reveal(container_id, instance_id, "common")).is_true()
	assert_that(orch.complete_reveal(container_id, instance_id, "def-1", "common", 10, Vector2i.ONE)).is_true()


## [Wiring] 编排器暴露 container_search() 访问器（领域接口类型）
func test_orchestrator_exposes_container_search() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	assert_that(orch.container_search()).is_not_null()
	assert_that(orch.container_search() is IContainerSearchService).is_true()
	## 经服务登记/打开容器端点可用
	_enter_run(orch)
	assert_that(orch.open_container("c-1", 2, ["i-1", "i-2"])).is_true()
	assert_that(orch.container_search().container("c-1")).is_not_null()
	assert_that(orch.container_search().container("c-1").item_count).is_equal(2)


## [Wiring] 局内完成 5 个容器：完成数按容器搜索域统计（INV-06），
## 达到阈值撤离解锁（INV-07）
func test_completing_required_containers_unlocks_extract() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_enter_run(orch)

	for i in 4:
		_complete_one(orch, "c-%d" % i, "i-%d" % i)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(0)

	## 第 5 个完成 -> 撤离解锁（INV-07）
	_complete_one(orch, "c-4", "i-4")
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)
	assert_that(store.read().completed_container_count).is_equal(5)


## [Wiring] 完成计数幂等（INV-06）：重复揭晓同一容器不重复计入局级完成数
func test_complete_reveal_idempotent_run_count() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_enter_run(orch)
	_complete_one(orch, "c-1", "i-1")
	assert_that(store.read().completed_container_count).is_equal(1)

	## 对已完成容器重复揭晓：返回 false，局级完成数不变（INV-06）
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(store.read().completed_container_count).is_equal(1)


## [Wiring] 局外守卫：容器搜索用例在局外无效，不污染领域状态
func test_container_search_guarded_out_of_run() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	orch.start()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)

	assert_that(orch.open_container("c-1", 1, ["i-1"])).is_false()
	assert_that(orch.start_reveal("c-1", "i-1", "common")).is_false()
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	## 未打开容器（未登记）且局级状态不被污染
	assert_that(orch.container_search().container("c-1")).is_null()
	assert_that(store.read().completed_container_count).is_equal(0)


## [Wiring] 新一局开始清空上局容器登记（INV-14 多局隔离）
func test_new_run_resets_container_registry() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	_enter_run(orch)
	_complete_one(orch, "c-1", "i-1")
	assert_that(orch.container_search().completed_container_count()).is_equal(1)

	## 走合法流程回局外：补足撤离解锁阈值 -> 撤离成功 -> 结算确认
	for i in 4:
		_complete_one(orch, "c-%d" % (i + 2), "i-%d" % (i + 2))
	orch.start_extraction()
	orch.complete_extraction_placeholder()
	orch.settle()
	orch.confirm_settled()
	## 再开新一局：容器登记被清空（INV-14）
	orch.request_start_match()
	assert_that(orch.confirm_loadout()).is_true()
	assert_that(orch.container_search().container("c-1")).is_null()
	assert_that(orch.container_search().completed_container_count()).is_equal(0)


## [Wiring] 本局地图容器计划：入场后按配置生成（AC-17 图形化容器实体来源；
## 数量读 GameConfig.match_container_count，INV-16 单一来源；id 唯一）
func test_match_containers_planned_per_run() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	## 入场前无本局容器
	assert_that(orch.match_containers()).is_empty()

	_enter_run(orch)
	var containers: Array = orch.match_containers()
	assert_that(containers.size()).is_equal(6)  # 默认配置 match_container_count
	var seen := {}
	for entry in containers:
		var cid := str(entry.get("container_id", ""))
		assert_that(cid).is_not_equal("")
		assert_that(seen.has(cid)).is_false()
		seen[cid] = true
		assert_that(str(entry.get("display_name", ""))).is_not_equal("")


## [Wiring] 未注入 ContainerSearchService：回退占位行为，既有流程不受影响
func test_fallback_without_container_search_service() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(), _FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	## 未接线时访问器返回 null，容器搜索用例返回 false
	assert_that(orch.container_search()).is_null()
	assert_that(orch.open_container("c-1", 1, ["i-1"])).is_false()
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	## 既有占位流程不受影响
	assert_that(orch.complete_container_placeholder()).is_equal(1)


## ---- 搜索弹窗分步流程（蒙版 -> 按品质揭晓 -> 手动搬运，V2）----

## 组装带 Loot/Container + Item/Inventory 域的编排器（分步流程被测主体）。
class _SeedStore:
	extends InMemoryDataStore

	func _init() -> void:
		seed_v01_defaults()


func _stepwise_orchestrator() -> Dictionary:
	var bus := _LocalBusAdapter.new(_bus)
	var store := _InMemoryStateStore.new()
	var run_session := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	var container_search := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	var item_inventory := ItemInventoryService.new(
		MemoryConfigDataRepository.new(_SeedStore.new()), bus)
	item_inventory.setup_backpack(6, 4)
	item_inventory.setup_safe(2, 2)
	var orch := RunFlowOrchestrator.new(bus, store, _FakeConfigLoader.new(),
		null, null, run_session, item_inventory, container_search)
	return {"orch": orch, "item_inventory": item_inventory, "store": store}


## [Wiring] 打开容器计划：返回蒙版块（位置+尺寸），不泄露物品身份（INV-05）
func test_container_plan_masks_identity() -> void:
	var parts := _stepwise_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	_enter_run(orch)

	var plan := orch.container_search_plan("map-c-01")
	assert_that(plan.is_empty()).is_false()
	assert_that(int(plan.get("item_count", 0))).is_greater_equal(1)
	var blocks: Array = plan.get("blocks", [])
	assert_that(blocks.size()).is_equal(int(plan.get("item_count", 0)))
	for b: Dictionary in blocks:
		## 摘要只含位置/尺寸/已揭晓标记，不含身份字段
		assert_that(b.has("pos")).is_true()
		assert_that(b.has("size")).is_true()
		assert_that(b.has("definition_id")).is_false()
		assert_that(b.has("rarity")).is_false()
		assert_that(bool(b.get("revealed", true))).is_false()
	## 重复打开返回同一计划（内容不重置）
	var again := orch.container_search_plan("map-c-01")
	assert_that(again.get("instance_ids", [])).is_equal(plan.get("instance_ids", []))


## [Wiring] 揭晓分步：reveal 返回品质与耗时（转速依据）；finish 揭晓身份并
## 推进完成计数；stow 搬运入背包/安全箱（搬运前实例不落地）
func test_reveal_finish_stow_flow() -> void:
	var parts := _stepwise_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var inv: ItemInventoryService = parts["item_inventory"]
	_enter_run(orch)

	var plan := orch.container_search_plan("map-c-01")
	var ids: Array = plan.get("instance_ids", [])
	var instance_id := str(ids[0])

	## 蒙版阶段实例不存在（未搬运不落地）
	assert_that(inv.get_item(instance_id)).is_null()

	var revealed := orch.reveal_container_item("map-c-01", instance_id)
	assert_that(revealed.is_empty()).is_false()
	assert_that(str(revealed.get("rarity", ""))).is_not_equal("")
	assert_that(float(revealed.get("wait_time", 0.0))).is_greater(0.0)

	var info := orch.finish_reveal_container_item("map-c-01", instance_id)
	assert_that(str(info.get("definition_id", ""))).is_not_equal("")
	## 揭晓完成但未搬运：仍不落地
	assert_that(inv.get_item(instance_id)).is_null()

	## 揭晓剩余物品使容器完成（INV-06：全部揭晓后才计完成数）
	for i in range(1, ids.size()):
		var rid := str(ids[i])
		assert_that(orch.reveal_container_item("map-c-01", rid).is_empty()).is_false()
		assert_that(orch.finish_reveal_container_item("map-c-01", rid).is_empty()).is_false()
	assert_that(orch.container_search().completed_container_count()).is_equal(1)

	## 搬运入背包 (0,0)：落实例并占格
	assert_that(orch.stow_revealed_item(instance_id,
			GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()
	var item: ItemInstance = inv.get_item(instance_id)
	assert_that(item).is_not_null()
	assert_that(item.location).is_equal(ItemInstance.Location.BACKPACK)
	var bp: GridInventory = inv.get_grid(GridInventory.OwnerType.BACKPACK)
	assert_that(bp.has(instance_id)).is_true()

	## 再搬运入安全箱（跨格移动）：背包腾出、安全箱占格
	var safe_at := Vector2i(1, 1)
	assert_that(orch.stow_revealed_item(instance_id,
			GridInventory.OwnerType.SAFE, safe_at)).is_true()
	assert_that(bp.has(instance_id)).is_false()
	var safe_grid: GridInventory = inv.get_grid(GridInventory.OwnerType.SAFE)
	assert_that(safe_grid.position_of(instance_id)).is_equal(safe_at)


## [Wiring] 仓库格子：结算入库摆位（first-fit）+ 拖拽重排 + 未知实例 1x1 占位
func test_warehouse_grid_placement() -> void:
	var parts := _stepwise_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var inv: ItemInventoryService = parts["item_inventory"]
	inv.setup_warehouse(8, 6)
	_enter_run(orch)

	## 未知实例（账本直登记、无实体）：给 1x1 坐标但不落实体
	var ghost_at := orch.ensure_warehouse_placement("ghost-item")
	assert_that(ghost_at).is_equal(Vector2i.ZERO)
	assert_that(inv.get_item("ghost-item")).is_null()

	## 真实例（3x3 弹药箱）入库：占据 first-fit 空位且不与占位块重叠
	assert_that(inv.create_item("wh-ammobox", "item_ammobox")).is_not_null()
	var at := orch.ensure_warehouse_placement("wh-ammobox")
	assert_that(at != Vector2i(-1, -1)).is_true()
	var wh: GridInventory = inv.get_grid(GridInventory.OwnerType.WAREHOUSE)
	assert_that(wh.size_of("wh-ammobox")).is_equal(Vector2i(3, 3))

	## 拖拽重排到空角（INV-04 校验）
	assert_that(orch.move_warehouse_item("wh-ammobox", Vector2i(5, 3))).is_true()
	assert_that(wh.position_of("wh-ammobox")).is_equal(Vector2i(5, 3))
	## 非法位置保持原位
	assert_that(orch.move_warehouse_item("wh-ammobox", Vector2i(7, 5))).is_false()
	assert_that(wh.position_of("wh-ammobox")).is_equal(Vector2i(5, 3))


## [Wiring] 旧用例兼容：search_and_carry_container 多件流程一次完成
## （打开+逐件揭晓+自动携带，返回契约不变）
func test_search_and_carry_multi_item_compat() -> void:
	var parts := _stepwise_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var inv: ItemInventoryService = parts["item_inventory"]
	inv.setup_warehouse(8, 6)
	_enter_run(orch)

	var result := orch.search_and_carry_container("map-c-01")
	assert_that(int(result.get("completed_count", 0))).is_equal(1)
	assert_that(int(result.get("carried_count", 0))).is_greater_equal(1)
	## 重复搜索同一容器幂等（INV-06）
	var again := orch.search_and_carry_container("map-c-01")
	assert_that(int(again.get("carried_count", -1))).is_equal(0)
