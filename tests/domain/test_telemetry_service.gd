## test_telemetry_service.gd —— FullHaul 领域测试：Telemetry（遥测）域（GdUnit4）
##
## 职责：
##   切片 9：验证 TelemetryService 的埋点行为：
##   - start() 后订阅全部领域事件，事件发布即留痕
##   - 事件名 / 摘要文本 / 计数 / 查询正确
##   - 遥测不作为产品规则来源（不修改任何领域数据）
##   - stop() 后退订，不再留痕
##   - clear() 清空记录
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_telemetry_service.gd --ignoreHeadlessMode

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


var _bus: Node = null
var _adapter: _LocalBusAdapter = null


func before_test() -> void:
	_bus = auto_free(EventBusScript.new())
	_bus.call("_ready")
	_adapter = _LocalBusAdapter.new(_bus)


## 组装已订阅全部事件的遥测服务。
func _telemetry() -> TelemetryService:
	var t := TelemetryService.new(_adapter)
	t.start()
	return t


## [Telemetry] start() 订阅全部事件：发布事件即留痕，事件名/摘要正确
func test_start_records_all_events() -> void:
	var t := _telemetry()

	_adapter.publish(DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.RunInitialized.new("run-0001", 180, 0, true, false))
	_adapter.publish(DomainEvents.Events.BACKPACK_PURCHASED,
		DomainEvents.BackpackPurchased.new("backpack_4x4", 1000, 100000, 99000))

	assert_that(t.count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(t.count(DomainEvents.Events.BACKPACK_PURCHASED)).is_equal(1)
	assert_that(t.has(DomainEvents.Events.RUN_INITIALIZED)).is_true()

	var entries := t.entries()
	assert_that(entries.size()).is_equal(2)
	var first: Dictionary = entries[0]
	assert_that(first.get("event_name")).is_equal("RUN_INITIALIZED")
	assert_that(str(first.get("summary"))).contains("run_id=run-0001")


## [Telemetry] 遥测不作为产品规则来源：只记录，不修改任何领域数据
func test_telemetry_does_not_modify_domain() -> void:
	var t := _telemetry()

	## 发布前状态
	_adapter.publish(DomainEvents.Events.CURRENCY_CHANGED,
		DomainEvents.CurrencyChanged.new(1000, 99000, 100000))

	assert_that(t.count(DomainEvents.Events.CURRENCY_CHANGED)).is_equal(1)
	assert_that(t.entries().size()).is_equal(1)
	## 不写 RunState / Profile：没有这些对象可写，只做纯记录
	assert_that(t.entries()[0].get("event_name")).is_equal("CURRENCY_CHANGED")


## [Telemetry] stop() 后退订：不再留痕
func test_stop_unsubscribes() -> void:
	var t := _telemetry()
	t.stop()

	_adapter.publish(DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.RunInitialized.new("run-0001", 180, 0, true, false))

	assert_that(t.entries().is_empty()).is_true()


## [Telemetry] clear() 清空记录，后续仍继续记录
func test_clear_resets_entries() -> void:
	var t := _telemetry()

	_adapter.publish(DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.RunInitialized.new("run-0001", 180, 0, true, false))
	assert_that(t.entries().size()).is_equal(1)

	t.clear()
	assert_that(t.entries().is_empty()).is_true()

	_adapter.publish(DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.RunInitialized.new("run-0002", 180, 0, true, false))
	assert_that(t.count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)


## [Telemetry] 未注入总线：start() 静默跳过，不报错
func test_no_bus_start_is_safe() -> void:
	var t := TelemetryService.new()
	t.start()
	## 无总线不订阅、不记录，也不抛错
	assert_that(t.entries().is_empty()).is_true()

## [Telemetry] UI_INTERACTED 交互事件：正常留痕且摘要含界面/动作/对象
func test_ui_interacted_recorded_with_summary() -> void:
	var t := _telemetry()

	_adapter.publish(DomainEvents.Events.UI_INTERACTED,
		DomainEvents.UiInteracted.new("match", "container_click", "crate_1", ""))

	assert_that(t.count(DomainEvents.Events.UI_INTERACTED)).is_equal(1)
	var summary := str(t.entries()[0].get("summary"))
	assert_that(summary).contains("screen=match")
	assert_that(summary).contains("action=container_click")
	assert_that(summary).contains("target=crate_1")


## [Telemetry] console_echo 开启：留痕行为不变（控制台打印无法断言，仅回归不抛错）
func test_console_echo_keeps_recording() -> void:
	var t := TelemetryService.new(_adapter)
	t.console_echo = true
	t.start()

	_adapter.publish(DomainEvents.Events.UI_INTERACTED,
		DomainEvents.UiInteracted.new("match", "search_button"))
	_adapter.publish(DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.RunInitialized.new("run-0001", 180, 0, true, false))

	assert_that(t.entries().size()).is_equal(2)
