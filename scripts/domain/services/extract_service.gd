## extract_service.gd —— FullHaul 领域服务：Extract（撤离）域
##
## 职责：
##   实现 IExtractService 契约（架构 §1.1 Extract 域、§2.1 顶层状态机
##   IN_RUN_EXTRACTABLE/EXTRACTING、§5 RunState 实体、规范 AC-09/10/11、
##   INV-07/08，切片 7）：
##   - 撤离锁定/解锁：完成数 >= 阈值解锁（INV-07），阈值读取配置单一来源
##   - 开始撤离：重置撤离读条为配置撤离时长（extraction_duration，INV-08）
##   - 双计时并行推进：撤离读条与总计时同步递减（INV-08）
##   - 成功/失败判定：读条先于总时间归零 -> 成功（RUN_SUCCEEDED）；
##     总时间先归零 -> 失败（RUN_FAILED）
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 领域事件（EXTRACT_STARTED/RUN_SUCCEEDED/RUN_FAILED 等）由顶层状态机
##      在转移时发布，本服务只负责撤离状态的推进与判定，不重复发布事件。
##   3. 一局一实例：经注入的 IRunStateStore 读写本局 RunState；禁止全局
##      静态单例承载运行态（审核 P1-3）。
##   4. 同刻计时优先级（读条与总时间同时归零）为规范 TBD-04，本实现按架构
##      §2.1 字面语义「读条必须严格先于总时间才判成功」，同刻归零判失败；
##      该边缘语义待产品决策，不私自扩展默认值之外的行为。

extends IExtractService
class_name ExtractService
## 本类继承领域接口 IExtractService（本文件为切片 7 的落地实现）。

## 注入的局内状态存储（一局一实例读写，可选）
var _state_store: IRunStateStore = null
## 注入的配置加载器（撤离时长/解锁阈值单一来源 INV-16）
var _config_loader: IConfigLoader = null
## 是否处于撤离读条推进中（start_extraction 置位，读条/总时间任一归零复位）
var _extracting := false
## 双计时不足 1 秒的浮点累积（帧级 delta 不足整秒时先攒后扣，
## 避免 int(delta) 截断为 0 导致读条/总时间停滞；start_extraction 复位）
var _tick_remainder := 0.0


func _init(state_store: IRunStateStore = null, config_loader: IConfigLoader = null) -> void:
	_state_store = state_store
	_config_loader = config_loader


## 撤离是否已解锁（完成数 >= 阈值，INV-07）。
func is_extract_unlocked(state: RunState) -> bool:
	if state == null:
		return false
	return state.completed_container_count >= _required_completed_containers()


## 开始撤离读条（INV-08）：重置读条为配置撤离时长，返回剩余撤离时间。
func start_extraction(state: RunState) -> int:
	if state == null:
		return 0
	_extracting = true
	_tick_remainder = 0.0
	state.remaining_extraction_time = _extraction_duration()
	_write(state)
	return state.remaining_extraction_time


## 推进撤离读条与总计时（并行递减，INV-08）。
## 帧级浮点 delta 先累积满整秒再同时扣减双计时（截断会让每帧 ~0.016s
## 全部丢失，读条停滞）。返回本次推进是否使撤离阶段落定：读条或总时间
## 任一归零即返回 true，由 is_success 判定成功（读条先归零）还是失败
## （总时间先归零）。
func tick(state: RunState, delta_seconds: float) -> bool:
	if state == null or not _extracting:
		return false
	if delta_seconds > 0.0:
		_tick_remainder += delta_seconds
		var whole := int(_tick_remainder)
		_tick_remainder -= whole
		if whole > 0:
			state.remaining_match_time = maxi(state.remaining_match_time - whole, 0)
			state.remaining_extraction_time = maxi(state.remaining_extraction_time - whole, 0)
			_write(state)
	if state.remaining_extraction_time <= 0 or state.remaining_match_time <= 0:
		_extracting = false
		return true
	return false


## 撤离是否成功（读条严格先于总时间归零，INV-08）。
## 同刻归零（读条与总时间同时为 0）为规范 TBD-04，按「读条须严格先于总时间」
## 的字面语义判为失败，待产品决策后调整。
func is_success(state: RunState) -> bool:
	if state == null:
		return false
	return state.remaining_extraction_time <= 0 and state.remaining_match_time > 0


## 撤离解锁所需完成容器数（配置单一来源 INV-16；未加载时回退默认 5）。
func _required_completed_containers() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.required_completed_containers
	return 5


## 撤离读条时长（配置单一来源 INV-16；未加载时回退默认 15）。
func _extraction_duration() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.extraction_duration
	return 15


## 状态变更写回局内状态存储（注入时；未注入则仅原地修改传入的 state）。
func _write(state: RunState) -> void:
	if _state_store != null:
		_state_store.write(state)