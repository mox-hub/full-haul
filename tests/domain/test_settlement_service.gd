## test_settlement_service.gd —— FullHaul 领域测试：Settlement 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 8 落地的 SettlementService（架构 §1.1
##   Settlement 域、§2.1 RUN_SUCCEEDED/RUN_FAILED -> SETTLED、§5 RunState 实体）。
##
## 覆盖映射：
##   - INV-10 / AC-12：成功结算——撤离成功携带物品入仓库
##   - INV-11 / AC-13：失败结算——撤离失败安全箱物品入仓库
##   - INV-09：单次结算幂等——结算标记置位后重复结算被忽略
##   - 未注入 Warehouse 时结算不落库物品（结果流转可回退）
##   - is_settled 查询
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_settlement_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 假仓库服务：内存记录 add_to_warehouse 调用
class _FakeWarehouse:
	extends IWarehouseService

	var added: Array = []

	func add_to_warehouse(profile: PlayerProfile, instance_id: String) -> void:
		if profile == null:
			return
		if not profile.warehouse_item_ids.has(instance_id):
			profile.warehouse_item_ids.append(instance_id)
		added.append(instance_id)

	func sell_item(_profile: PlayerProfile, _instance_id: String) -> int:
		return 0


## 组装被测 SettlementService（注入假仓库）。
func _service() -> Dictionary:
	var warehouse := _FakeWarehouse.new()
	var svc := SettlementService.new(warehouse)
	return {"svc": svc, "warehouse": warehouse}


## 创建一个终局状态（可指定成败与物品 id 列表）。
func _terminal(success: bool, carried: Array = [], safe: Array = []) -> RunState:
	var state := RunState.new("run-x", 180, 15)
	state.set_phase(RunState.Phase.RUN_SUCCEEDED if success else RunState.Phase.RUN_FAILED)
	state.carried_item_ids = carried
	state.safe_item_ids = safe
	return state


## [SettlementService] INV-10/AC-12：成功结算——撤离成功携带物品入仓库
func test_settle_success_stores_carried_items() -> void:
	var parts := _service()
	var svc: SettlementService = parts["svc"]
	var warehouse: _FakeWarehouse = parts["warehouse"]
	var profile := PlayerProfile.new(100000)
	var state := _terminal(true, ["i-c1", "i-c2"])

	assert_that(svc.settle_success(state, profile)).is_true()
	assert_that(profile.warehouse_item_ids).contains_exactly(["i-c1", "i-c2"])
	assert_that(warehouse.added).contains_exactly(["i-c1", "i-c2"])


## [SettlementService] INV-11/AC-13：失败结算——撤离失败安全箱物品入仓库
func test_settle_failure_stores_safe_items() -> void:
	var parts := _service()
	var svc: SettlementService = parts["svc"]
	var warehouse: _FakeWarehouse = parts["warehouse"]
	var profile := PlayerProfile.new(100000)
	var state := _terminal(false, [], ["i-s1", "i-s2"])

	assert_that(svc.settle_failure(state, profile)).is_true()
	assert_that(profile.warehouse_item_ids).contains_exactly(["i-s1", "i-s2"])
	assert_that(warehouse.added).contains_exactly(["i-s1", "i-s2"])


## [SettlementService] INV-09：单次结算幂等——结算标记置位后重复结算被忽略
func test_settle_idempotent_after_marked() -> void:
	var parts := _service()
	var svc: SettlementService = parts["svc"]
	var warehouse: _FakeWarehouse = parts["warehouse"]
	var profile := PlayerProfile.new(100000)
	var state := _terminal(true, ["i-c1"])

	assert_that(svc.settle_success(state, profile)).is_true()
	assert_that(warehouse.added).contains_exactly(["i-c1"])

	## 结算标记置位后：重复结算返回 false 且不重复入库（INV-09）
	state.settled = true
	assert_that(svc.settle_success(state, profile)).is_false()
	assert_that(svc.settle_failure(state, profile)).is_false()
	assert_that(warehouse.added).contains_exactly(["i-c1"])
	assert_that(profile.warehouse_item_ids).contains_exactly(["i-c1"])


## [SettlementService] 未注入 Warehouse：结算不落库物品（结果流转可回退）
func test_settle_without_warehouse_does_not_store() -> void:
	var svc := SettlementService.new()
	var profile := PlayerProfile.new(100000)
	var state := _terminal(true, ["i-c1"])

	assert_that(svc.settle_success(state, profile)).is_true()
	assert_that(profile.warehouse_item_ids.is_empty()).is_true()


## [SettlementService] is_settled 查询（INV-09）
func test_is_settled_query() -> void:
	var parts := _service()
	var svc: SettlementService = parts["svc"]
	var state := _terminal(true)

	assert_that(svc.is_settled(state)).is_false()
	state.settled = true
	assert_that(svc.is_settled(state)).is_true()
	assert_that(svc.is_settled(null)).is_false()


## [SettlementService] 空状态：结算被拒绝（不落库、不标记）
func test_settle_null_state_rejected() -> void:
	var parts := _service()
	var svc: SettlementService = parts["svc"]
	var warehouse: _FakeWarehouse = parts["warehouse"]

	assert_that(svc.settle_success(null, PlayerProfile.new(0))).is_false()
	assert_that(svc.settle_failure(null, PlayerProfile.new(0))).is_false()
	assert_that(warehouse.added.is_empty()).is_true()
