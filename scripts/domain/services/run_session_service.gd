## run_session_service.gd —— FullHaul 领域服务：RunSession（局内会话）域
##
## 职责：
##   实现 IRunSessionService 契约（架构 §1.1 RunSession 域、§5 RunState 实体、
##   AC-03）。承载一局内的会话状态：
##   - 每局一个 Run 实例（runId、阶段、双计时、完成容器数、settled）
##   - 双计时：全局计时（remaining_match_time，总时间）与当前目标计时
##     （remaining_extraction_time，撤离读条）
##   - 完成容器数计数（INV-06/INV-07 依赖完成数）
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 一局一实例：经注入的 IRunStateStore 读写本局 RunState；禁止全局
##      静态单例承载运行态（审核 P1-3）。
##   3. 领域事件（RUN_INITIALIZED）经注入的 IEventBus 发布，供表现层/遥测
##      订阅；领域层不依赖 Autoload 节点。
##   4. 双计时推进为纯函数式 tick：全局计时归零 -> 失败（INV-07/08）；
##      当前目标（撤离读条）归零 -> 成功（INV-08）。同刻计时优先级为规范
##      TBD-04，本切片不做同刻判定，只分别报告各计时是否归零。

extends IRunSessionService
class_name RunSessionService
## 本类继承领域接口 IRunSessionService（本文件为切片 4 的落地实现）。

## 注入的局内状态存储（一局一实例读写）
var _state_store: IRunStateStore = null
## 注入的事件总线（RUN_INITIALIZED 发布）
var _bus: IEventBus = null
## 注入的配置加载器（撤离解锁阈值单一来源 INV-16）
var _config_loader: IConfigLoader = null


func _init(state_store: IRunStateStore, bus: IEventBus, config_loader: IConfigLoader) -> void:
	_state_store = state_store
	_bus = bus
	_config_loader = config_loader


## 创建一局 Run 实例（AC-03）。
## 返回本局 RunState；经状态存储持久化，并发布 RUN_INITIALIZED 事件
## （matchDuration、完成数=0、撤离锁定、settled=false）。
func create_run(run_id: String, match_duration: int, extraction_duration: int) -> RunState:
	var state := RunState.new(run_id, match_duration, extraction_duration)
	state.set_phase(RunState.Phase.RUN_INIT)
	_state_store.write(state)
	if _bus != null:
		_bus.publish(DomainEvents.Events.RUN_INITIALIZED, DomainEvents.RunInitialized.new(
			run_id, match_duration, 0, true, false))
	return state


## 读取当前局 RunState。
func current_run() -> RunState:
	return _state_store.read()


## 写入（更新）当前局 RunState。
func save_run(state: RunState) -> void:
	_state_store.write(state)


## 记录完成一个容器（INV-06/INV-07 依赖完成数）。
func on_container_completed(state: RunState) -> void:
	if state == null:
		return
	state.completed_container_count += 1
	_state_store.write(state)


## 推进本局全局计时（总时间）。
## 返回是否已归零（总时间=0 -> RUN_FAILED，INV-07/08）。
func tick_match_time(delta_seconds: float) -> bool:
	var state := current_run()
	if state == null:
		return false
	state.remaining_match_time = maxi(state.remaining_match_time - int(delta_seconds), 0)
	_state_store.write(state)
	return state.remaining_match_time <= 0


## 推进当前目标计时（撤离读条）。
## 返回是否已归零（读条先归零 -> RUN_SUCCEEDED，INV-08）。
func tick_extraction_time(delta_seconds: float) -> bool:
	var state := current_run()
	if state == null:
		return false
	state.remaining_extraction_time = maxi(state.remaining_extraction_time - int(delta_seconds), 0)
	_state_store.write(state)
	return state.remaining_extraction_time <= 0


## 撤离是否已解锁（完成数 >= 阈值，INV-07）。
## 阈值读取配置单一来源（INV-16）；未加载配置时回退默认 5。
func is_extract_unlocked(state: RunState) -> bool:
	if state == null:
		return false
	return state.completed_container_count >= required_completed_containers()


## 撤离解锁所需完成容器数（配置单一来源 INV-16）。
func required_completed_containers() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.required_completed_containers
	return 5