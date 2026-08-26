## test_warehouse_service.gd —— FullHaul 领域测试：Warehouse 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 8 落地的 WarehouseService（架构 §1.1
##   Warehouse 域、§5 PlayerProfile 实体、规范 AC-14、INV-12）。
##
## 覆盖映射：
##   - 物品入库：撤离成功物品入仓库（重复入库幂等）
##   - INV-12 / AC-14：出售物品——货币加款原子化 + 从仓库移除
##   - 防重：同一物品只允许售出一次（Transaction 防重，INV-12）
##   - 余额/价值边界：物品不在仓库 / 价值非正 / 未注入解析器拒绝出售
##   - 未注入 Transaction 时回退直接加款
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_warehouse_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 组装被测 WarehouseService（注入内存事务后端 + 价值解析器）。
func _service(value: int) -> Dictionary:
	var store := InMemoryDataStore.new()
	var tx := TransactionService.new(MemoryRunResultRepository.new(store))
	var svc := WarehouseService.new(tx, func(_instance_id: String) -> int: return value)
	return {"svc": svc, "store": store}


## [WarehouseService] 物品入库：撤离成功物品加入仓库（重复入库幂等）
func test_add_to_warehouse_idempotent() -> void:
	var svc := WarehouseService.new()
	var profile := PlayerProfile.new(100000)

	svc.add_to_warehouse(profile, "i-c1")
	svc.add_to_warehouse(profile, "i-c1")
	svc.add_to_warehouse(profile, "i-c2")

	assert_that(profile.warehouse_item_ids).contains_exactly(["i-c1", "i-c2"])


## [WarehouseService] 空参数：不入库、不崩溃
func test_add_to_warehouse_guards() -> void:
	var svc := WarehouseService.new()
	var profile := PlayerProfile.new(100000)

	svc.add_to_warehouse(profile, "")
	svc.add_to_warehouse(null, "i-c1")
	assert_that(profile.warehouse_item_ids.is_empty()).is_true()


## [WarehouseService] INV-12/AC-14：出售物品——货币加款 + 从仓库移除 + 事务流水
func test_sell_item_credits_and_removes() -> void:
	var parts := _service(500)
	var svc: WarehouseService = parts["svc"]
	var store: InMemoryDataStore = parts["store"]
	var profile := PlayerProfile.new(1000)
	svc.add_to_warehouse(profile, "i-c1")

	var price := svc.sell_item(profile, "i-c1")
	assert_that(price).is_equal(500)
	assert_that(profile.currency).is_equal(1500)
	assert_that(profile.warehouse_item_ids.is_empty()).is_true()
	## 事务流水已记录（type=sell，INV-12 防重）
	assert_that(store.transactions.size()).is_equal(1)
	assert_that(store.transactions[0].get("type")).is_equal("sell")
	assert_that(store.transactions[0].get("amount")).is_equal(500)


## [WarehouseService] 防重：同一物品只允许售出一次（Transaction 防重，INV-12）
func test_sell_item_dedupe_blocks_second_sale() -> void:
	var parts := _service(500)
	var svc: WarehouseService = parts["svc"]
	var profile := PlayerProfile.new(1000)
	svc.add_to_warehouse(profile, "i-c1")

	assert_that(svc.sell_item(profile, "i-c1")).is_equal(500)
	assert_that(profile.currency).is_equal(1500)
	## 第二次出售：物品已移出仓库，返回 0，不再加款
	assert_that(svc.sell_item(profile, "i-c1")).is_equal(0)
	assert_that(profile.currency).is_equal(1500)


## [WarehouseService] 边界：物品不在仓库 / 价值非正 / 空参数拒绝出售
func test_sell_item_rejects_invalid() -> void:
	var parts := _service(0)
	var svc: WarehouseService = parts["svc"]
	var profile := PlayerProfile.new(1000)

	## 价值非正（解析器返回 0）：拒绝
	svc.add_to_warehouse(profile, "i-zero")
	assert_that(svc.sell_item(profile, "i-zero")).is_equal(0)
	assert_that(profile.currency).is_equal(1000)

	## 物品不在仓库：拒绝
	assert_that(svc.sell_item(profile, "i-nope")).is_equal(0)
	## 空参数：拒绝
	assert_that(svc.sell_item(profile, "")).is_equal(0)


## [WarehouseService] 未注入 Transaction：回退直接加款（可独立测试）
func test_sell_item_fallback_without_tx() -> void:
	var svc := WarehouseService.new(null, func(_instance_id: String) -> int: return 300)
	var profile := PlayerProfile.new(1000)
	svc.add_to_warehouse(profile, "i-c1")

	assert_that(svc.sell_item(profile, "i-c1")).is_equal(300)
	assert_that(profile.currency).is_equal(1300)
	assert_that(profile.warehouse_item_ids.is_empty()).is_true()
