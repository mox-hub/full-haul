## i_run_session_service.gd —— FullHaul 领域接口：RunSession（局内会话）域
##
## 职责：
##   定义局内会话域对应用编排层暴露的最小契约（架构 §1.1 RunSession 域、
##   §5 RunState 实体）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-03，切片 4）：
##   - 每局一个 Run 实例（runId、阶段、双计时、完成容器数、settled）
##   - 双计时：全局计时（总时间）与当前目标计时（撤离读条）
##   - 完成数计数（INV-06/INV-07 依赖完成数）
##   - 禁止全局静态单例承载运行态（审核 P1-3）：一局一实例，经接口注入
##
## 说明：切片 4 由 RunSessionService 落地实现本契约（架构 §7 切片 4）。

extends RefCounted
class_name IRunSessionService

## 创建一局 Run 实例（AC-03）：runId 唯一、双计时初始化、完成数=0、
## 撤离锁定、settled=false；返回 RunState。
func create_run(run_id: String, match_duration: int, extraction_duration: int) -> RunState:
	return null


## 读取当前局 RunState（无则返回 null）。
func current_run() -> RunState:
	return null


## 写入（更新）当前局 RunState。
func save_run(state: RunState) -> void:
	pass


## 记录完成一个容器（INV-06/INV-07 依赖完成数）。
func on_container_completed(state: RunState) -> void:
	pass


## 推进本局全局计时（总时间）；返回是否已归零（总时间=0 -> RUN_FAILED，
## INV-07/08）。
func tick_match_time(delta_seconds: float) -> bool:
	return false


## 推进当前目标计时（撤离读条）；返回是否已归零（读条先归零 ->
## RUN_SUCCEEDED，INV-08）。
func tick_extraction_time(delta_seconds: float) -> bool:
	return false


## 撤离是否已解锁（完成数 >= 阈值，INV-07）。
func is_extract_unlocked(state: RunState) -> bool:
	return false
