## test_item_inventory_wiring.gd —— FullHaul 接线测试：Item & Inventory 接入编排器（GdUnit4）
##
## 职责：
##   切片 5：验证 RunFlowOrchestrator 接入 Item & Inventory 域后的接线行为：
##   - 确认入场时按选定档位初始化本局背包格子（尺寸单一来源 INV-16）
##   - 同时初始化安全箱格子（配置 SafeContainerConfig）
##   - 编排器暴露 item_inventory() 访问器（供表现层/后续切片经接口访问）
##   - 未注入 ItemInventoryService 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_item_inventory_wiring.gd --ignoreHeadlessMode

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


## 假配置数据仓储：种子物品定义（INV-16 单一来源）
class _FakeConfigRepo:
	extends IConfigDataRepository
	var item_definitions: Dictionary = {}

	func _init() -> void:
		item_definitions = {
			"item_1x1": {"definition_id": "item_1x1", "name": "电池", "rarity": "common",
				"width": 1, "height": 1, "value": 10},
		}

	func load_item_definitions() -> Dictionary:
		return item_definitions

	func get_item_definition(definition_id: String) -> Dictionary:
		return item_definitions.get(definition_id, {})


var _bus: Node = null


func before_test() -> void:
	_bus = auto_free(EventBusScript.new())
	_bus.call("_ready")


## 组装带 Item & Inventory 域的编排器。
func _wired_orchestrator() -> Dictionary:
	var bus := _LocalBusAdapter.new(_bus)
	var item_inventory := ItemInventoryService.new(_FakeConfigRepo.new(), bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), null, null, null, item_inventory)
	return {"orch": orch, "item_inventory": item_inventory}


## [Wiring] 确认入场：按选定档位初始化背包格子 + 安全箱格子（INV-04/INV-16）
func test_confirm_loadout_sets_up_grids() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var item_inventory: ItemInventoryService = parts["item_inventory"]

	orch.start()
	orch.request_start_match()
	## 选择 5x5 档位（默认 GameConfig 第二档）
	assert_that(orch.select_backpack("backpack_5x5")).is_true()
	orch.confirm_loadout()

	## 背包格子按档位尺寸初始化（5x5）
	var backpack := item_inventory.get_grid(GridInventory.OwnerType.BACKPACK)
	assert_that(backpack).is_not_null()
	assert_that(backpack.width).is_equal(5)
	assert_that(backpack.height).is_equal(5)
	## 安全箱格子按配置初始化（2x2）
	var safe := item_inventory.get_grid(GridInventory.OwnerType.SAFE)
	assert_that(safe).is_not_null()
	assert_that(safe.width).is_equal(2)
	assert_that(safe.height).is_equal(2)


## [Wiring] 编排器暴露 item_inventory() 访问器（领域接口类型）
func test_orchestrator_exposes_item_inventory() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	assert_that(orch.item_inventory()).is_not_null()
	assert_that(orch.item_inventory() is IItemInventoryService).is_true()
	## 经服务创建实例并放置到背包格子（AC-07 端点可用）；
	## 先初始化背包格子（模拟确认入场已绑定档位）
	var item_inventory: IItemInventoryService = orch.item_inventory()
	item_inventory.setup_backpack(4, 4)
	assert_that(item_inventory.create_item("i-1", "item_1x1")).is_not_null()
	assert_that(item_inventory.place_item("i-1",
		GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)).is_true()


## [Wiring] 未注入 ItemInventoryService：回退占位行为，既有流程不受影响
func test_fallback_without_item_inventory_service() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(),
		_FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	## 未接线时访问器返回 null
	assert_that(orch.item_inventory()).is_null()