## EventBus —— FullHaul 全局事件总线（Autoload 基础设施）
##
## 职责：
##   作为游戏内所有领域事件的唯一流转通道（对应架构文档 §2.3 关键事件流）。
##   领域层、应用层、表现层均通过本总线发布/订阅领域事件，模块之间不直接
##   持有对方实例（依赖注入 + 事件订阅，架构原则 3）。
##
## 设计要点：
##   1. 事件类型与事件数据类统一在 `DomainEvents`（纯数据类，领域层共享）
##      中定义；本 Autoload 只负责「注册表 + 派发」，不重复定义事件。
##   2. 订阅使用 Callable 回调，返回一个订阅 id，可随时退订。
##   3. 本总线只承载「事件流转」，不承载任何业务运行态（Run/货币/仓库等
##      运行态一律由每局/每局外实例承载并经接口注入，架构原则/审核 P1-3）。
##
## 使用示例：
##   # 发布一个事件
##   EventBus.publish(DomainEvents.Events.CURRENCY_CHANGED, DomainEvents.CurrencyChanged.new(...))
##
##   # 订阅一个事件（返回 subId 可退订）
##   var sub_id := EventBus.subscribe(DomainEvents.Events.RUN_INITIALIZED, _on_run_initialized)
##   EventBus.unsubscribe(DomainEvents.Events.RUN_INITIALIZED, sub_id)

extends Node

## 内部：每个事件类型对应的订阅回调表（event -> { sub_id -> Callable }）
var _subscribers: Dictionary = {}

## 内部：订阅 id 自增计数器
var _next_sub_id := 0


func _ready() -> void:
	## 初始化每个事件类型的订阅表，避免运行时动态建表
	for event_id in DomainEvents.Events.values():
		_subscribers[event_id] = {}


## 订阅一个事件。
## 返回订阅 id（int），可用 unsubscribe 退订。
func subscribe(event_id: int, callback: Callable) -> int:
	assert(event_id in DomainEvents.Events.values(), "EventBus.subscribe: 未知事件类型 %d" % event_id)
	_next_sub_id += 1
	var sub_id := _next_sub_id
	_subscribers[event_id][sub_id] = callback
	return sub_id


## 退订一个事件订阅。
func unsubscribe(event_id: int, sub_id: int) -> void:
	if event_id in _subscribers and sub_id in _subscribers[event_id]:
		_subscribers[event_id].erase(sub_id)


## 发布一个事件（同步派发给所有订阅者）。
## payload 为 DomainEvents 中对应事件类的实例。
func publish(event_id: int, payload: RefCounted = null) -> void:
	assert(event_id in _subscribers, "EventBus.publish: 未知事件类型 %d" % event_id)
	for sub_id in _subscribers[event_id]:
		var cb: Callable = _subscribers[event_id][sub_id]
		cb.call(payload)


## 清空所有订阅（主要用于测试隔离）。
func clear_all() -> void:
	for event_id in DomainEvents.Events.values():
		_subscribers[event_id] = {}
