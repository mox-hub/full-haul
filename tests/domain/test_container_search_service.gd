## test_container_search_service.gd —— FullHaul 领域测试：Loot / Container 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 6 落地的 ContainerSearchService（架构 §1.1
##   Loot / Container 域、§2.2 容器搜索子状态机、§5 ContainerState 实体、
##   AC-04/05/06/17/18、INV-05/06）：
##   - 容器登记（一局一个容器一个实例，重复登记拒绝）
##   - 打开进入 MASKED（INV-05 遮罩计数）与逐件揭晓（品质决定耗时）
##   - 完成计数幂等（INV-06）：completed_container_count 只统计已 counted 容器
##   - 事件发布（CONTAINER_OPENED/ITEM_REVEAL_STARTED/ITEM_REVEALED/CONTAINER_COMPLETED）
##   - reset 多局隔离（INV-14）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_container_search_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


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


## 假配置加载器：返回默认 GameConfig（品质揭晓耗时单一来源 INV-16）
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


## 组装被测服务。
func _service() -> Dictionary:
	var bus := _FakeEventBus.new()
	var svc := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	return {"svc": svc, "bus": bus}


## 完整走完一个容器（打开 -> 逐件揭晓 -> 完成）。
func _complete_container(svc: ContainerSearchService, container_id: String,
		instance_ids: Array) -> void:
	svc.open_container(container_id, instance_ids.size(), instance_ids)
	for instance_id in instance_ids:
		assert_that(svc.start_reveal(container_id, instance_id, "common")).is_true()
		svc.complete_reveal(container_id, instance_id, "def-%s" % instance_id,
			"common", 10, Vector2i.ONE)


## [ContainerSearchService] 登记：一局一个容器一个实例，重复登记拒绝
func test_register_container() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]

	assert_that(svc.register_container("c-1", "crate_1")).is_true()
	assert_that(svc.register_container("c-1", "crate_2")).is_false()
	var csm := svc.container("c-1")
	assert_that(csm).is_not_null()
	assert_that(csm.container_id).is_equal("c-1")
	assert_that(csm.type_id).is_equal("crate_1")
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.UNOPENED)
	assert_that(svc.container("nope")).is_null()


## [ContainerSearchService] 打开容器：进入 MASKED 并发布 CONTAINER_OPENED（INV-05）
func test_open_container_publishes_opened() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	assert_that(svc.open_container("c-1", 3)).is_true()
	assert_that(svc.is_container_completed("c-1")).is_false()
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_OPENED)).is_true()
	var payload: DomainEvents.ContainerOpened = bus.last_payload(DomainEvents.Events.CONTAINER_OPENED)
	assert_that(payload.container_id).is_equal("c-1")
	assert_that(payload.unknown_count).is_equal(3)
	assert_that(payload.shapes.size()).is_equal(3)

	## 重复打开被忽略
	assert_that(svc.open_container("c-1", 5)).is_false()
	assert_that(svc.container("c-1").item_count).is_equal(3)


## [ContainerSearchService] 逐件揭晓：品质决定耗时（配置单一来源 INV-16），
## 全部揭晓后完成并发布事件（AC-05/06）
func test_reveal_flow_until_completed() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]

	svc.open_container("c-1", 2, ["i-1", "i-2"])

	## 第一件：开始揭晓（common -> 0.5s 配置）并完成
	assert_that(svc.start_reveal("c-1", "i-1", "common")).is_true()
	var started: DomainEvents.ItemRevealStarted = bus.last_payload(DomainEvents.Events.ITEM_REVEAL_STARTED)
	assert_that(started.instance_id).is_equal("i-1")
	assert_that(started.rarity).is_equal("common")
	assert_that(started.wait_time).is_equal(0.5)
	assert_that(svc.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(bus.has_published(DomainEvents.Events.ITEM_REVEALED)).is_true()
	assert_that(svc.is_container_completed("c-1")).is_false()

	## 第二件：完成时返回首次完成信号（INV-06）
	svc.start_reveal("c-1", "i-2", "epic")
	assert_that(svc.complete_reveal("c-1", "i-2", "def-2", "epic", 200, Vector2i.ONE)).is_true()
	assert_that(svc.is_container_completed("c-1")).is_true()
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_COMPLETED)).is_true()


## [ContainerSearchService] 完成计数幂等（INV-06）：多容器累计，重复完成不重复计数
func test_completed_count_idempotent() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]

	## 完成两个容器
	_complete_container(svc, "c-1", ["i-1", "i-2"])
	_complete_container(svc, "c-2", ["i-3"])
	assert_that(svc.completed_container_count()).is_equal(2)

	## 对已完成容器再次完成揭晓：不重复计数（INV-06 幂等）
	assert_that(svc.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(svc.completed_container_count()).is_equal(2)

	## 未完成容器不计入
	svc.open_container("c-3", 2, ["i-4", "i-5"])
	svc.start_reveal("c-3", "i-4", "common")
	svc.complete_reveal("c-3", "i-4", "def-4", "common", 10, Vector2i.ONE)
	assert_that(svc.is_container_completed("c-3")).is_false()
	assert_that(svc.completed_container_count()).is_equal(2)


## [ContainerSearchService] 揭晓守卫（INV-05）：未打开/未登记的容器不可开始或完成揭晓
func test_reveal_guarded_on_unknown_or_unopened() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]

	## 未登记容器
	assert_that(svc.start_reveal("ghost", "i-1", "common")).is_false()
	assert_that(svc.complete_reveal("ghost", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(svc.is_container_completed("ghost")).is_false()

	## 已登记未打开（UNOPENED）
	svc.register_container("c-1")
	assert_that(svc.start_reveal("c-1", "i-1", "common")).is_false()
	assert_that(svc.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()


## [ContainerSearchService] 提供实例 id 时遮罩计数与实例数一致（遮罩与最终尺寸一致）
func test_open_aligns_count_with_instance_ids() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]

	assert_that(svc.open_container("c-1", 99, ["i-1", "i-2", "i-3"])).is_true()
	var csm := svc.container("c-1")
	assert_that(csm.item_count).is_equal(3)
	assert_that(csm.item_instance_ids.size()).is_equal(3)


## [ContainerSearchService] reset：新一局清空容器登记（INV-14 多局隔离）
func test_reset_isolates_runs() -> void:
	var parts := _service()
	var svc: ContainerSearchService = parts["svc"]

	_complete_container(svc, "c-1", ["i-1"])
	assert_that(svc.completed_container_count()).is_equal(1)

	## 新一局开始清空
	svc.reset()
	assert_that(svc.completed_container_count()).is_equal(0)
	assert_that(svc.container("c-1")).is_null()
	## 新局可重新登记同名容器
	assert_that(svc.register_container("c-1")).is_true()
	assert_that(svc.open_container("c-1", 1, ["i-1"])).is_true()
