## main.gd —— FullHaul 启动入口（应用编排层 / 表现层入口）
##
## 职责：
##   作为工程主场景，负责基础框架的启动引导（对应架构 §6 切片 1）：
##     1. 初始化配置加载（ConfigLoader，单一来源）
##     2. 初始化事件总线（EventBus，全局事件流转通道）
##     3. 校验配置合法性；失败则进入 ERROR 态（规范 4.2）
##     4. 挂载领域层顶层状态机的启动（BOOT -> OUT_OF_RUN）
##
## 说明：
##   本文件为「基础框架」的最小可运行入口，后续各域切片（Loadout/Loot/
##   Extract/Settlement 等）将在此基础上接入场景与 UI。

extends Node

## 顶层状态机实例（每局一个，由后续切片注入领域依赖）
var _state_machine: TopLevelStateMachine = null


func _ready() -> void:
	_boot_framework()


## 基础框架启动引导。
func _boot_framework() -> void:
	## 1. 加载并校验全局配置
	var ok := ConfigLoader.load_config()
	if not ok:
		## 配置加载/校验失败 -> 记录错误并进入 ERROR 态，禁止带错运行
		push_error("FullHaul 启动失败：%s" % ConfigLoader.last_error)
		return

	print("FullHaul 基础框架启动：配置加载成功（matchDuration=%d）" % ConfigLoader.config.match_duration)

	## 2. 事件总线就绪（Autoload 已实例化，此处可订阅全局事件）
	EventBus.subscribe(DomainEvents.Events.OUT_OF_RUN_ENTERED, _on_out_of_run_entered)

	## 3. 领域层依赖注入并启动顶层状态机（后续切片替换为真实存储实现）
	var store := _InMemoryRunStateStore.new()
	_state_machine = TopLevelStateMachine.new(EventBusAdapter.new(), store, ConfigLoaderAdapter.new())
	_state_machine.boot()
	_state_machine.on_boot_ok()

	print("FullHaul 基础框架就绪：进入 OUT_OF_RUN")


func _on_out_of_run_entered(_payload: RefCounted) -> void:
	print("FullHaul 事件总线：OUT_OF_RUN_ENTERED 已广播")


## ---- 适配器：把领域层接口桥接到全局 Autoload 基础设施 ----

## 事件总线适配器：领域层通过它发布/订阅到全局 EventBus
class EventBusAdapter:
	extends IEventBus

	func publish(event_id: int, payload: RefCounted = null) -> void:
		EventBus.publish(event_id, payload)

	func subscribe(event_id: int, callback: Callable) -> int:
		return EventBus.subscribe(event_id, callback)

	func unsubscribe(event_id: int, sub_id: int) -> void:
		EventBus.unsubscribe(event_id, sub_id)


## 配置加载适配器：领域层通过它读取全局配置
class ConfigLoaderAdapter:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return ConfigLoader.get_config()


## 内存版局内状态存储（V0.1 运行周期内；跨重启持久化按 TBD-12）
class _InMemoryRunStateStore:
	extends IRunStateStore

	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state