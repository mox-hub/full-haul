## test_run_state.gd —— FullHaul 地基测试：RunState 局内状态模型（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §5 RunState 实体与规范不变量，作为领域层
##   地基测试的一部分（WORD-25）。
##
## 覆盖映射：
##   - INV-09 结算幂等：settled 标记只置位一次，重复 mark_settled 返回 false
##   - 状态单向受控：phase 初值、可写入
##   - 局内临时状态与局外状态分离（INV-13）：本模型只承载局内字段
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_run_state.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [RunState] 结算幂等：首次标记成功，重复标记忽略（INV-09）
func test_settled_idempotent() -> void:
	var state := RunState.new("run-1", 180, 15)
	assert_that(state.settled).is_false()
	assert_that(state.mark_settled()).is_true()
	assert_that(state.settled).is_true()
	## 重复标记应被幂等忽略（INV-09）
	assert_that(state.mark_settled()).is_false()
	assert_that(state.settled).is_true()


## [RunState] 初值：构造时处于 RUN_INIT，双计时取自配置
func test_initial_state() -> void:
	var state := RunState.new("run-2", 180, 15)
	assert_that(state.run_id).is_equal("run-2")
	assert_that(state.phase).is_equal(RunState.Phase.RUN_INIT)
	assert_that(state.remaining_match_time).is_equal(180)
	assert_that(state.remaining_extraction_time).is_equal(15)
	assert_that(state.completed_container_count).is_equal(0)
	assert_that(state.settled).is_false()


## [RunState] 局内临时状态字段存在且可读写（INV-13 局内/局外分离的局内侧）
func test_run_state_fields() -> void:
	var state := RunState.new()
	state.set_phase(RunState.Phase.IN_RUN_LOCKED)
	assert_that(state.phase).is_equal(RunState.Phase.IN_RUN_LOCKED)
	state.completed_container_count = 3
	assert_that(state.completed_container_count).is_equal(3)
	state.carried_item_ids = ["i-1", "i-2"]
	state.safe_item_ids = ["s-1"]
	assert_that(state.carried_item_ids).contains_exactly(["i-1", "i-2"])
	assert_that(state.safe_item_ids).contains_exactly(["s-1"])
