## event_bus_interface.gd —— FullHaul 事件总线接口（领域层契约）
##
## 领域层通过本接口发布/订阅领域事件，不直接依赖 Autoload EventBus，
## 便于在测试中注入 mock 总线（架构 §3 接口原则、审核 P1-3）。

extends RefCounted
class_name IEventBus


## 发布一个事件
func publish(event_id: int, payload: RefCounted = null) -> void:
	pass


## 订阅一个事件，返回 sub_id
func subscribe(event_id: int, callback: Callable) -> int:
	return 0


## 退订
func unsubscribe(event_id: int, sub_id: int) -> void:
	pass
