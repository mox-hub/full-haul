## i_extract_service.gd —— FullHaul 领域接口：Extract（撤离）域
##
## 职责：
##   定义撤离域对应用编排层暴露的最小契约（架构 §1.1 Extract 域、
##   §2.1 顶层状态机 EXTRACTING/IN_RUN_EXTRACTABLE）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-09/10/11、INV-07/08，切片 7）：
##   - 撤离锁定/解锁（完成数阈值，INV-07）
##   - 15 秒撤离读条与总计时并行推进（INV-08）
##   - 成功/失败判定（读条先完成 -> RUN_SUCCEEDED；总时间先为 0 -> RUN_FAILED）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 7）落地。

extends RefCounted
class_name IExtractService

## 撤离是否已解锁（完成数 >= 阈值，INV-07）。
func is_extract_unlocked(state: RunState) -> bool:
	return false


## 开始撤离读条（INV-08），返回剩余撤离时间。
func start_extraction(state: RunState) -> int:
	return 0


## 推进撤离读条与总计时；返回本次推进是否使撤离完成（读条先归零）。
func tick(state: RunState, delta_seconds: float) -> bool:
	return false


## 撤离是否成功（读条先于总时间完成）。
func is_success(state: RunState) -> bool:
	return false
