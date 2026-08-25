## test_memory_repositories.gd —— FullHaul 数据层接线测试：内存仓储实现（GdUnit4）
##
## 职责：
##   WORD-31 阶段2：验证内存后端（InMemoryDataStore + Memory* 仓储）符合
##   领域仓储接口的语义：
##   - IConfigDataRepository：配置数据读取（道具/藏品/容器/背包档位/权重）
##   - IProfileRepository：局外账户读写（货币/仓库/已选背包）
##   - IRunResultRepository：结算记录幂等（INV-09）+ 事务防重（INV-12）
##   - IRunSnapshotRepository：局内状态快照（运行时数据，可选）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/infrastructure/test_memory_repositories.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [MemoryConfigDataRepository] 配置数据读取：种子数据可读、缺省返回空
func test_config_data_read_seeded() -> void:
	var store := InMemoryDataStore.new()
	store.item_definitions = {"item_001": {"definition_id": "item_001", "name": "能量饮料"}}
	store.backpack_offers = {"backpack_4x4": {"offer_id": "backpack_4x4", "price": 1000}}
	store.container_types = {"crate_1": {"type_id": "crate_1", "kind": "container"}}
	store.container_tier_weights = {"C1": {"common": 60, "rare": 10}}

	var repo := MemoryConfigDataRepository.new(store)
	assert_that(repo.load_item_definitions().has("item_001")).is_true()
	assert_that(repo.get_item_definition("item_001").get("name")).is_equal("能量饮料")
	assert_that(repo.get_item_definition("nope").is_empty()).is_true()
	assert_that(repo.load_backpack_offers().has("backpack_4x4")).is_true()
	assert_that(repo.load_container_types().has("crate_1")).is_true()
	assert_that(repo.load_container_tier_weights().get("C1").get("common")).is_equal(60)


## [MemoryConfigDataRepository] 空数据源：各读取返回空集合而非报错
func test_config_data_read_empty() -> void:
	var repo := MemoryConfigDataRepository.new(InMemoryDataStore.new())
	assert_that(repo.load_item_definitions().is_empty()).is_true()
	assert_that(repo.get_item_definition("x").is_empty()).is_true()
	assert_that(repo.load_container_types().is_empty()).is_true()
	assert_that(repo.load_backpack_offers().is_empty()).is_true()
	assert_that(repo.load_container_tier_weights().is_empty()).is_true()


## [MemoryProfileRepository] 局外账户读写往返（货币/仓库/已选背包）
func test_profile_save_load_roundtrip() -> void:
	var store := InMemoryDataStore.new()
	var repo := MemoryProfileRepository.new(store)

	var profile := repo.load()
	assert_that(profile.currency).is_equal(0)
	profile.currency = 5000
	profile.selected_backpack_offer_id = "backpack_5x5"
	profile.warehouse_item_ids = ["w-1", "w-2"]
	repo.save(profile)

	var reread := repo.load()
	assert_that(reread.currency).is_equal(5000)
	assert_that(reread.selected_backpack_offer_id).is_equal("backpack_5x5")
	assert_that(reread.warehouse_item_ids).contains_exactly(["w-1", "w-2"])


## [MemoryProfileRepository] 共享数据源：同一账户跨仓储实例可读回
func test_profile_shared_store_across_instances() -> void:
	var store := InMemoryDataStore.new()
	MemoryProfileRepository.new(store).save(_profile_with(2500, ["w-9"]))

	var fresh := MemoryProfileRepository.new(store).load()
	assert_that(fresh.currency).is_equal(2500)
	assert_that(fresh.warehouse_item_ids).contains_exactly(["w-9"])


## [MemoryRunResultRepository] 结算记录：插入/查询/重复 run_id 拒绝（INV-09）
func test_settlement_insert_find_dedupe() -> void:
	var store := InMemoryDataStore.new()
	var repo := MemoryRunResultRepository.new(store)

	var rec := {
		"record_id": "settle-1", "run_id": "run-0001", "profile_id": "local",
		"result": "success", "currency_before": 100, "currency_after": 100,
		"carried_item_ids": ["i-1"], "safe_item_ids": [],
	}
	assert_that(repo.insert_settlement(rec)).is_true()
	assert_that(repo.find_settlement_by_run("run-0001").get("result")).is_equal("success")
	## 幂等：同 run_id 重复写入被拒绝
	var dup := rec.duplicate(true)
	dup["record_id"] = "settle-1-dup"
	assert_that(repo.insert_settlement(dup)).is_false()
	assert_that(repo.find_settlement_by_run("missing").is_empty()).is_true()


## [MemoryRunResultRepository] 事务防重：同 profile+type+ref 拒绝（INV-12）
func test_transaction_dedupe() -> void:
	var repo := MemoryRunResultRepository.new(InMemoryDataStore.new())
	var entry := {
		"transaction_id": "t-1", "profile_id": "local", "type": "purchase",
		"amount": -1000, "ref_id": "backpack_5x5",
		"balance_before": 5000, "balance_after": 4000,
	}
	assert_that(repo.insert_transaction(entry)).is_true()
	assert_that(repo.has_transaction("local", "purchase", "backpack_5x5")).is_true()
	assert_that(repo.insert_transaction(entry)).is_false()
	assert_that(repo.has_transaction("local", "sell", "backpack_5x5")).is_false()


## [MemoryRunSnapshotRepository] 快照：upsert 幂等覆盖 + 按 run_id 读取
func test_run_snapshot_upsert_load() -> void:
	var store := InMemoryDataStore.new()
	var repo := MemoryRunSnapshotRepository.new(store)

	var state := RunState.new("run-0001", 180, 15)
	state.set_phase(RunState.Phase.IN_RUN_LOCKED)
	state.completed_container_count = 3
	assert_that(repo.upsert_run_snapshot(state)).is_true()

	var loaded := repo.load_run_snapshot("run-0001")
	assert_that(loaded).is_not_null()
	assert_that(loaded.run_id).is_equal("run-0001")
	assert_that(loaded.completed_container_count).is_equal(3)

	## 覆盖更新
	state.completed_container_count = 5
	repo.upsert_run_snapshot(state)
	assert_that(repo.load_run_snapshot("run-0001").completed_container_count).is_equal(5)
	assert_that(repo.load_run_snapshot("missing")).is_null()


func _profile_with(p_currency: int, warehouse: Array) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.currency = p_currency
	p.warehouse_item_ids = warehouse.duplicate()
	return p