## test_infrastructure.gd —— FullHaul 地基测试：Autoload 基础设施（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §6 切片 1 的 Autoload 基础设施：
##   EventBus（事件总线）与 ConfigLoader（配置加载器）。
##
## 覆盖映射：
##   - 事件总线：订阅/发布/退订（架构 §4 事件总线建议，事件流转唯一通道）
##   - 配置加载器：load_config 成功/失败、单一来源（INV-16）
##   - 基础设施不承载业务运行态（P1-3）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_infrastructure.gd --ignoreHeadlessMode

extends GdUnitTestSuite

## 通过 load() 加载 Autoload 脚本（Autoload 全局名不可直接 new，需用脚本资源实例化）
const EventBusScript := preload("res://autoload/EventBus.gd")
const ConfigLoaderScript := preload("res://autoload/ConfigLoader.gd")

var _received: Array = []


func before_test() -> void:
	_received = []


func _on_event(payload: RefCounted) -> void:
	_received.append(payload)


## [EventBus] 订阅/发布/退订：事件流转唯一通道
func test_event_bus_subscribe_publish_unsubscribe() -> void:
	var bus: Node = EventBusScript.new()
	bus.call("_ready")
	var sub_id: int = bus.call("subscribe", DomainEvents.Events.RUN_INITIALIZED, _on_event)

	bus.call("publish", DomainEvents.Events.RUN_INITIALIZED, DomainEvents.RunInitialized.new("run-1"))
	assert_that(_received.size()).is_equal(1)

	bus.call("unsubscribe", DomainEvents.Events.RUN_INITIALIZED, sub_id)
	bus.call("publish", DomainEvents.Events.RUN_INITIALIZED, DomainEvents.RunInitialized.new("run-2"))
	assert_that(_received.size()).is_equal(1)

	bus.free()


## [EventBus] 不同事件类型互不串扰
func test_event_bus_isolation() -> void:
	var bus: Node = EventBusScript.new()
	bus.call("_ready")
	var sub_id: int = bus.call("subscribe", DomainEvents.Events.RUN_INITIALIZED, _on_event)

	bus.call("publish", DomainEvents.Events.EXTRACT_STARTED, DomainEvents.ExtractStarted.new(15))
	assert_that(_received.is_empty()).is_true()

	bus.call("unsubscribe", DomainEvents.Events.RUN_INITIALIZED, sub_id)
	bus.free()


## [EventBus] clear_all 清空订阅（测试隔离）
func test_event_bus_clear_all() -> void:
	var bus: Node = EventBusScript.new()
	bus.call("_ready")
	bus.call("subscribe", DomainEvents.Events.RUN_INITIALIZED, _on_event)
	bus.call("clear_all")
	bus.call("publish", DomainEvents.Events.RUN_INITIALIZED, DomainEvents.RunInitialized.new("run-x"))
	assert_that(_received.is_empty()).is_true()
	bus.free()


## [ConfigLoader] 默认配置加载成功（INV-16 单一来源）
func test_config_loader_default() -> void:
	var loader: Node = ConfigLoaderScript.new()
	var ok: bool = loader.call("load_config")
	assert_that(ok).is_true()
	assert_that(loader.get("config")).is_not_null()
	assert_that(loader.get("config").match_duration).is_equal(180)
	assert_that(loader.get("last_error")).is_equal("")
	loader.free()


## [ConfigLoader] 外部 JSON 不存在 -> 加载失败且置错
func test_config_loader_missing_json() -> void:
	var loader: Node = ConfigLoaderScript.new()
	var ok: bool = loader.call("load_config", "res://data/does_not_exist.json")
	assert_that(ok).is_false()
	assert_that(loader.get("last_error")).is_not_empty()
	loader.free()


## [ConfigLoader] 基础设施不承载业务运行态：config 为 GameConfig 资源而非局内运行态
func test_config_loader_no_run_state() -> void:
	var loader: Node = ConfigLoaderScript.new()
	loader.call("load_config")
	var config: Variant = loader.get("config")
	assert_that(config is GameConfig).is_true()
	## 基础设施只承载配置，不承载 RunState 等局内运行态字段
	assert_that("run_id" in config).is_false()
	assert_that("settled" in config).is_false()
	loader.free()
