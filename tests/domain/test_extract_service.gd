## test_extract_service.gd —— FullHaul 领域测试：Extract 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 7 落地的 ExtractService（架构 §1.1 Extract 域、
##   §2.1 EXTRACTING、§5 RunState 实体）。
##
## 覆盖映射：
##   - INV-07 / AC-09：撤离锁定/解锁（完成数 >= 配置阈值解锁）
##   - INV-08 / AC-10：开始撤离重置读条（撤离时长单一来源 INV-16）
##   - INV-08 / AC-11：撤离读条与总计时并行推进
##   - 成功判定：读条先于总时间归零 -> 成功（RUN_SUCCEEDED）
##   - 失败判定：总时间先归零 -> 失败（RUN_FAILED）
##   - 同刻归零（TBD-04）：按「读条须严格先于总时间」判失败（文档化边缘语义）
##   - 未开始撤离时 tick 不推进
##   - 状态变更写回 IRunStateStore（一局一实例，P1-3）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_extract_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 假配置加载器：返回默认 GameConfig
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


## 可定制数值的配置加载器（验证配置单一来源 INV-16）
class _CustomConfigLoader:
	extends IConfigLoader

	var _cfg: GameConfig

	func _init(cfg: GameConfig) -> void:
		_cfg = cfg

	func get_config() -> GameConfig:
		return _cfg


## 内存态局内状态存储
class _InMemoryStateStore:
	extends IRunStateStore

	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state


## 组装被测 ExtractService（默认配置）。
func _service() -> Dictionary:
	var store := _InMemoryStateStore.new()
	var svc := ExtractService.new(store, _FakeConfigLoader.new())
	return {"svc": svc, "store": store}


## 创建一个指定双计时起点的局内状态（模拟已进入一局）。
func _run(match_duration: int, extraction_duration: int) -> RunState:
	var state := RunState.new("run-x", match_duration, extraction_duration)
	state.set_phase(RunState.Phase.EXTRACTING)
	return state


## [ExtractService] INV-07：完成数达到配置阈值后撤离解锁
func test_is_extract_unlocked_threshold() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var state := _run(180, 15)

	## 默认阈值 5（配置单一来源 INV-16）
	for i in 4:
		state.completed_container_count = i + 1
		assert_that(svc.is_extract_unlocked(state)).is_false()
	state.completed_container_count = 5
	assert_that(svc.is_extract_unlocked(state)).is_true()
	state.completed_container_count = 6
	assert_that(svc.is_extract_unlocked(state)).is_true()


## [ExtractService] INV-07/INV-16：解锁阈值读取配置（required_completed_containers）
func test_is_extract_unlocked_custom_threshold() -> void:
	var cfg := GameConfig.new()
	cfg.required_completed_containers = 3
	var svc := ExtractService.new(null, _CustomConfigLoader.new(cfg))
	var state := _run(180, 15)

	state.completed_container_count = 2
	assert_that(svc.is_extract_unlocked(state)).is_false()
	state.completed_container_count = 3
	assert_that(svc.is_extract_unlocked(state)).is_true()


## [ExtractService] INV-08：开始撤离重置读条为配置撤离时长并返回
func test_start_extraction_resets_bar() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var store: _InMemoryStateStore = parts["store"]
	var state := _run(180, 15)

	## 默认撤离时长 15（配置单一来源 INV-16）
	assert_that(svc.start_extraction(state)).is_equal(15)
	assert_that(state.remaining_extraction_time).is_equal(15)
	assert_that(store.read().remaining_extraction_time).is_equal(15)


## [ExtractService] INV-16：撤离时长读取配置（extraction_duration）
func test_start_extraction_custom_duration() -> void:
	var cfg := GameConfig.new()
	cfg.extraction_duration = 20
	var svc := ExtractService.new(null, _CustomConfigLoader.new(cfg))
	var state := _run(180, 20)

	assert_that(svc.start_extraction(state)).is_equal(20)
	assert_that(state.remaining_extraction_time).is_equal(20)


## [ExtractService] INV-08/AC-11 成功路径：读条先于总时间归零 -> 成功
func test_tick_parallel_success() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var store: _InMemoryStateStore = parts["store"]
	var state := _run(180, 15)
	svc.start_extraction(state)

	## 双计时并行递减：总时间与读条同步推进
	assert_that(svc.tick(state, 5.0)).is_false()
	assert_that(state.remaining_match_time).is_equal(175)
	assert_that(state.remaining_extraction_time).is_equal(10)
	assert_that(svc.tick(state, 5.0)).is_false()
	assert_that(state.remaining_match_time).is_equal(170)
	assert_that(state.remaining_extraction_time).is_equal(5)

	## 读条先归零（总时间仍有剩余）-> 撤离落定且判成功
	assert_that(svc.tick(state, 5.0)).is_true()
	assert_that(state.remaining_extraction_time).is_equal(0)
	assert_that(state.remaining_match_time).is_equal(165)
	assert_that(svc.is_success(state)).is_true()
	## 状态写回存储（P1-3）
	assert_that(store.read().remaining_extraction_time).is_equal(0)


## [ExtractService] INV-08/AC-11 失败路径：总时间先归零 -> 失败
func test_tick_parallel_failure() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var state := _run(10, 15)
	svc.start_extraction(state)

	assert_that(svc.tick(state, 8.0)).is_false()
	assert_that(state.remaining_match_time).is_equal(2)
	assert_that(state.remaining_extraction_time).is_equal(7)

	## 总时间先归零（读条仍有剩余）-> 撤离落定且判失败
	assert_that(svc.tick(state, 3.0)).is_true()
	assert_that(state.remaining_match_time).is_equal(0)
	assert_that(state.remaining_extraction_time).is_equal(4)
	assert_that(svc.is_success(state)).is_false()


## [ExtractService] TBD-04：读条与总时间同刻归零 -> 按「读条须严格先于总时间」
## 字面语义判失败（待产品决策的边缘语义）
func test_tick_simultaneous_zero_resolves_failure() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var state := _run(15, 15)
	svc.start_extraction(state)

	assert_that(svc.tick(state, 15.0)).is_true()
	assert_that(state.remaining_match_time).is_equal(0)
	assert_that(state.remaining_extraction_time).is_equal(0)
	assert_that(svc.is_success(state)).is_false()


## [ExtractService] 未开始撤离时 tick 不推进（start_extraction 前置）
func test_tick_before_start_is_noop() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var state := _run(180, 15)

	assert_that(svc.tick(state, 5.0)).is_false()
	assert_that(state.remaining_match_time).is_equal(180)
	assert_that(state.remaining_extraction_time).is_equal(15)


## [ExtractService] 撤离落定后不再推进（_extracting 复位）
func test_tick_after_resolution_is_noop() -> void:
	var parts := _service()
	var svc: ExtractService = parts["svc"]
	var state := _run(180, 15)
	svc.start_extraction(state)

	## 读条（配置撤离时长 15）一次性耗完 -> 落定
	assert_that(svc.tick(state, 15.0)).is_true()
	assert_that(state.remaining_match_time).is_equal(165)

	## 落定后再 tick：不再推进（避免撤离阶段外持续耗表）
	var match_before := state.remaining_match_time
	assert_that(svc.tick(state, 5.0)).is_false()
	assert_that(state.remaining_match_time).is_equal(match_before)