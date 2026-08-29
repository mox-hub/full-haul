## telemetry_service.gd —— FullHaul 领域服务：Telemetry（遥测）域
##
## 职责：
##   实现 ITelemetryService 契约（架构 §1.1 Config & Telemetry 域、§2.3
##   「遥测域订阅上述全部事件做埋点」，规范 6.4）：
##   - 订阅全部领域事件，逐条留痕（事件类型 + 事件名 + 摘要文本 + 时间戳）
##   - 提供只读查询（entries/count/has）与清空，供诊断/验证/回放
##
## 设计要点：
##   1. 纯逻辑：extends RefCounted，零 Godot 节点依赖，可独立单元测试
##      （架构原则 2）。
##   2. 遥测只做「记录/埋点」，绝不作为产品规则来源（规范 6.4）；不参与
##      状态机、不写入 RunState、不改动任何领域数据。
##   3. 订阅经注入的 IEventBus（依赖注入，架构原则 3）；start() 订阅全部
##      事件，stop() 退订全部，避免测试间订阅残留。
##   4. 一条记录 = { event_id, event_name, at_ms, summary }；summary 由
##      事件数据类提取为可读文本（字段缺失时回退 "()"）。

extends ITelemetryService
class_name TelemetryService
## 本类继承领域接口 ITelemetryService（本文件为切片 9 的落地实现）。

## 注入的事件总线（订阅全部领域事件）
var _bus: IEventBus = null
## 已记录的遥测条目：Array[Dictionary]
var _entries: Array = []
## 事件类型 -> 订阅 id（start 登记 / stop 退订）
var _sub_ids: Dictionary = {}
## 控制台回显开关：true 时每条事件留痕同时 print 一行日志（组合根打开，
## 默认关闭避免测试输出刷屏）。日志形如：
##   [遥测][+1234 ms] CONTAINER_OPENED(container_id=c1 unknown_count=2)
var console_echo := false


func _init(bus: IEventBus = null) -> void:
	_bus = bus


## 开始订阅全部领域事件（架构 §2.3「遥测域订阅上述全部事件」）。
func start() -> void:
	if _bus == null or not _sub_ids.is_empty():
		return
	for event_id in DomainEvents.Events.values():
		var captured: int = event_id
		_sub_ids[event_id] = _bus.subscribe(event_id,
			func(payload: RefCounted): _record(captured, payload))


## 停止订阅并清除已注册的订阅（不再留痕）。
func stop() -> void:
	if _bus == null:
		return
	for event_id in _sub_ids:
		_bus.unsubscribe(event_id, _sub_ids[event_id])
	_sub_ids.clear()


## 已记录的全部遥测条目（数组拷贝，避免外部修改）。
func entries() -> Array:
	return _entries.duplicate(true)


## 指定事件类型的记录次数。
func count(event_id: int) -> int:
	var n := 0
	for entry in _entries:
		if entry.get("event_id", -1) == event_id:
			n += 1
	return n


## 是否已记录过指定事件类型。
func has(event_id: int) -> bool:
	return count(event_id) > 0


## 清空已记录条目（测试/诊断用）。
func clear() -> void:
	_entries.clear()


## 记录一条遥测事件（start 后由订阅回调触发）；console_echo 开启时同步
## 打印一行到控制台（Godot 标准输出）。
func _record(event_id: int, payload: RefCounted) -> void:
	var at_ms := Time.get_ticks_msec()
	var summary := _summarize(event_id, payload)
	_entries.append({
		"event_id": event_id,
		"event_name": _event_name(event_id),
		"at_ms": at_ms,
		"summary": summary,
	})
	if console_echo:
		print("[遥测][+%d ms] %s" % [at_ms, summary])


## 事件类型 -> 可读事件名（枚举键）。
func _event_name(event_id: int) -> String:
	for key in DomainEvents.Events:
		if DomainEvents.Events[key] == event_id:
			return str(key)
	return "EVENT_%d" % event_id


## 从事件数据类提取可读摘要（纯展示文本，不承载任何逻辑）。
## 字段缺失/数据类未识别时回退 "()"，不抛错。
func _summarize(event_id: int, payload: RefCounted) -> String:
	var parts: Array = []
	if payload != null:
		for prop in payload.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var name: String = prop.name
				if name.begins_with("_"):
					continue
				var value: Variant = payload.get(name)
				parts.append("%s=%s" % [name, _to_text(value)])
	return "%s(%s)" % [_event_name(event_id), " ".join(parts)]


## Variant -> 文本（数组压缩为元素数；Vector2i 保留坐标）。
func _to_text(value: Variant) -> String:
	if value is Array:
		return "[%d]" % value.size()
	if value is Vector2i:
		return "(%d,%d)" % [value.x, value.y]
	return str(value)