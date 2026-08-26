## test_container_search_state_machine.gd —— FullHaul 地基测试：
##   容器搜索子状态机（Loot/Container 域，GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §2.2 容器搜索子状态机（规范 4.3）。
##
## 覆盖映射：
##   - INV-05 遮罩不泄露：UNOPENED 不得开始揭晓；MASKED 只含数量与形状
##   - INV-06 完成计数幂等：同一容器只 +1 一次（counted）
##   - AC-04/05/06/17/18/19 搜索/揭晓/完成流程
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_container_search_state_machine.gd --ignoreHeadlessMode

extends GdUnitTestSuite

## 简单事件总线 mock（记录发布的事件 id）
class _FakeEventBus:
	extends IEventBus
	var published: Array[int] = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append(event_id)

	func has_published(event_id: int) -> bool:
		return event_id in published


## [ContainerSearchStateMachine] 全流程：UNOPENED->MASKED->REVEALING->PARTIALLY_REVEALED->COMPLETED（架构 §2.2）
func test_full_flow() -> void:
	var bus := _FakeEventBus.new()
	var csm := ContainerSearchStateMachine.new("c-1", bus, null)

	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.UNOPENED)

	## 首次打开 -> MASKED（INV-05）
	csm.open(3)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_OPENED)).is_true()

	## 逐件揭晓
	assert_that(csm.start_reveal("i-1", "common")).is_true()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.REVEALING)
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.PARTIALLY_REVEALED)

	csm.start_reveal("i-2", "rare")
	csm.complete_reveal("i-2", "def-2", "rare", 50, Vector2i.ONE)
	csm.start_reveal("i-3", "epic")
	csm.complete_reveal("i-3", "def-3", "epic", 200, Vector2i.ONE)

	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.COMPLETED)
	assert_that(csm.is_completed()).is_true()
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_COMPLETED)).is_true()


## [ContainerSearchStateMachine] 完成计数幂等：同一容器只 +1 一次（INV-06）
func test_completed_count_idempotent() -> void:
	var csm := ContainerSearchStateMachine.new("c-2", null, null)
	csm.open(1)
	csm.start_reveal("i-1", "common")
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)

	assert_that(csm.is_completed()).is_true()
	assert_that(csm.was_counted()).is_true()

	## 重复揭晓/完成不得重复计数（INV-06 幂等）
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.is_completed()).is_true()
	assert_that(csm.was_counted()).is_true()


## [ContainerSearchStateMachine] 遮罩不泄露（INV-05）：UNOPENED 不可开始揭晓，重复打开不改变计数
func test_mask_no_leak() -> void:
	var csm := ContainerSearchStateMachine.new("c-3", null, null)

	## UNOPENED 阶段不可开始揭晓（未打开不得暴露身份）
	assert_that(csm.start_reveal("i-1", "common")).is_false()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.UNOPENED)

	csm.open(2)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)

	## 重复打开应被忽略（INV-05：计数/形状保持）
	csm.open(5)
	assert_that(csm.item_count).is_equal(2)


## [ContainerSearchStateMachine] MASKED 遮罩态只含数量与同尺寸占格（INV-05/AC-18）
func test_masked_shapes_uniform() -> void:
	var bus := _FakeEventBus.new()
	var csm := ContainerSearchStateMachine.new("c-4", bus, null)
	csm.open(4)
	assert_that(csm.item_count).is_equal(4)
	## 遮罩形状一律 1x1 同尺寸，不泄露身份/形状差异（INV-05）
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)


## [ContainerSearchStateMachine] 全部揭晓完成后不可再开始新揭晓（COMPLETED 终态）
func test_completed_is_terminal() -> void:
	var csm := ContainerSearchStateMachine.new("c-5", null, null)
	csm.open(1)
	csm.start_reveal("i-1", "common")
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.is_completed()).is_true()
	## 终态不可再开始揭晓
	assert_that(csm.start_reveal("i-2", "common")).is_false()


## [ContainerSearchStateMachine] 揭晓守卫（INV-05）：未开始揭晓（MASKED）不得完成揭晓
func test_reveal_without_start_guarded() -> void:
	var csm := ContainerSearchStateMachine.new("c-6", null, null)
	csm.open(1)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)
	## MASKED 直接完成揭晓应被拒绝（须先 start_reveal，INV-05 不泄露身份）
	assert_that(csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)


## [ContainerSearchStateMachine] 物品揭晓幂等：同一实例只揭晓一次，不重复计入已揭晓数
func test_same_instance_reveal_idempotent() -> void:
	var csm := ContainerSearchStateMachine.new("c-7", null, null)
	csm.open(2)
	## 同一实例重复揭晓：第二次不重复计入，也不推进阶段/完成
	assert_that(csm.start_reveal("i-1", "common")).is_true()
	assert_that(csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(csm.revealed_count).is_equal(1)
	assert_that(csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(csm.revealed_count).is_equal(1)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.PARTIALLY_REVEALED)
	## 另一实例揭晓后仍未完成，第二件完成时才计数（INV-06）
	csm.start_reveal("i-2", "rare")
	assert_that(csm.complete_reveal("i-2", "def-2", "rare", 50, Vector2i.ONE)).is_true()
	assert_that(csm.is_completed()).is_true()
	assert_that(csm.was_counted()).is_true()


## [ContainerSearchStateMachine] 打开时提供实例 id：遮罩计数与实例数一致（遮罩与最终尺寸一致）
func test_open_with_instance_ids_aligns_count() -> void:
	var csm := ContainerSearchStateMachine.new("c-8", null, null)
	## 提供实例列表时以实例数为准（忽略传入的 item_count，保证遮罩计数一致）
	assert_that(csm.open(99, ["i-1", "i-2", "i-3"])).is_true()
	assert_that(csm.item_count).is_equal(3)
	assert_that(csm.item_instance_ids.size()).is_equal(3)
	assert_that(csm.item_instance_ids.has("i-1")).is_true()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)
