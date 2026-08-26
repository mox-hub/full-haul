## i_telemetry_service.gd —— FullHaul 领域接口：Telemetry（遥测）域
##
## 职责：
##   定义遥测域对应用编排层暴露的最小契约（架构 §1.1 Config & Telemetry 域、
##   §2.3「遥测域订阅上述全部事件做埋点」）。
##
## 设计要点：
##   1. 遥测只做「记录/埋点」，绝不作为产品规则来源（规范 6.4）。
##   2. 订阅全部领域事件并留痕，供诊断/验证/回放使用。
##   3. 纯逻辑（extends RefCounted），经注入的 IEventBus 订阅，可独立测试。

extends RefCounted
class_name ITelemetryService

## 开始订阅全部领域事件（启动后事件开始留痕）。
func start() -> void:
	pass


## 停止订阅并清除已注册的订阅（不再留痕）。
func stop() -> void:
	pass


## 已记录的全部遥测条目（数组拷贝）。
func entries() -> Array:
	return []


## 指定事件类型的记录次数（无记录返回 0）。
func count(event_id: int) -> int:
	return 0


## 是否已记录过指定事件类型。
func has(event_id: int) -> bool:
	return false


## 清空已记录条目（测试/诊断用）。
func clear() -> void:
	pass