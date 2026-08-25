## i_run_session_service.gd —— FullHaul 领域接口：RunSession（局内状态）域
##
## 职责：
##   定义局内状态域对应用编排层暴露的最小契约（架构 §1.1 RunSession 域、
##   §5 RunState 实体）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-03，切片 4）：
##   - 每局一个 Run 实例（runId、阶段、双计时、完成容器数、settled）
##   - 禁止全局静态单例承载运行态（审核 P1-3）：一局一实例，经接口注入
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 4）落地。

extends RefCounted
class_name IRunSessionService

## 创建一局 Run 实例（AC-03），返回 RunState。
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
