## test_repository_provider.gd —— FullHaul 数据层接线测试：仓储装配与配置切换（GdUnit4）
##
## 职责：
##   WORD-31 阶段2：验证 RepositoryProvider 按配置（fullhaul/db/backend）
##   装配内存后端仓储，并解析后端类型：
##   - 默认（未配置/非法值）回退内存后端；
##   - 显式 memory / sqlite 配置正确解析；
##   - create_set() 装配的内存后端四仓储齐全、共享同一数据源。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/infrastructure/test_repository_provider.gd --ignoreHeadlessMode

extends GdUnitTestSuite


func before_test() -> void:
	## 清理可能残留的配置，保证用例从默认态开始
	ProjectSettings.set_setting(RepositoryProvider.SETTING_BACKEND, RepositoryProvider.DEFAULT_BACKEND)


## [RepositoryProvider] 默认后端：未配置时回退内存
func test_resolve_backend_default_memory() -> void:
	ProjectSettings.set_setting(RepositoryProvider.SETTING_BACKEND, "")
	assert_that(RepositoryProvider.resolve_backend()).is_equal(RepositoryProvider.BACKEND_MEMORY)


## [RepositoryProvider] 显式配置 sqlite / memory 均正确解析
func test_resolve_backend_explicit() -> void:
	ProjectSettings.set_setting(RepositoryProvider.SETTING_BACKEND, RepositoryProvider.BACKEND_SQLITE)
	assert_that(RepositoryProvider.resolve_backend()).is_equal(RepositoryProvider.BACKEND_SQLITE)

	ProjectSettings.set_setting(RepositoryProvider.SETTING_BACKEND, RepositoryProvider.BACKEND_MEMORY)
	assert_that(RepositoryProvider.resolve_backend()).is_equal(RepositoryProvider.BACKEND_MEMORY)


## [RepositoryProvider] 非法后端值回退内存
func test_resolve_backend_invalid_falls_back_memory() -> void:
	ProjectSettings.set_setting(RepositoryProvider.SETTING_BACKEND, "bogus")
	assert_that(RepositoryProvider.resolve_backend()).is_equal(RepositoryProvider.BACKEND_MEMORY)


## [RepositoryProvider] 内存后端装配：四仓储齐全
func test_create_memory_set_has_all_repos() -> void:
	var set := RepositoryProvider.create_set()
	assert_that(set.config_data).is_not_null()
	assert_that(set.profile).is_not_null()
	assert_that(set.run_result).is_not_null()
	assert_that(set.run_snapshot).is_not_null()


## [RepositoryProvider] 内存后端装配：接口语义可跑通（共享数据源）
func test_create_memory_set_roundtrip_via_interfaces() -> void:
	var set := RepositoryProvider.create_set()

	## 配置数据经接口读取（切片 9：内存后端已种子化 V0.1 默认配置，单一来源 INV-16）
	set.config_data.load_backpack_offers()
	assert_that(set.config_data.load_item_definitions().is_empty()).is_false()
	assert_that(set.config_data.load_item_definitions().has("item_battery")).is_true()

	## 局外账户经接口读写
	var profile: PlayerProfile = set.profile.load()
	profile.currency = 777
	profile.warehouse_item_ids = ["w-1"]
	set.profile.save(profile)
	assert_that(set.profile.load().currency).is_equal(777)

	## 结算记录经接口写入并读回
	assert_that(set.run_result.insert_settlement({
		"record_id": "s-1", "run_id": "run-x", "profile_id": "local",
		"result": "success", "currency_before": 0, "currency_after": 0,
		"carried_item_ids": [], "safe_item_ids": [],
	})).is_true()
	assert_that(set.run_result.find_settlement_by_run("run-x").get("record_id")).is_equal("s-1")

	## 快照经接口写入并读回
	var state := RunState.new("run-x", 180, 15)
	assert_that(set.run_snapshot.upsert_run_snapshot(state)).is_true()
	assert_that(set.run_snapshot.load_run_snapshot("run-x")).is_not_null()