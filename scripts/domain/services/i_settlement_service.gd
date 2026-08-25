## i_settlement_service.gd —— FullHaul 领域接口：Settlement（结算）域
##
## 职责：
##   定义结算域对应用编排层暴露的最小契约（架构 §1.1 Settlement 域、
##   §2.1 RUN_SUCCEEDED/RUN_FAILED -> SETTLED）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-12/13/14/15、INV-09，切片 8）：
##   - 成功/失败结算
##   - 单次结算幂等（INV-09，mark_settled）
##   - 结果流转至局外（Profile/Warehouse）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 8）落地。

extends RefCounted
class_name ISettlementService

## 执行一次成功结算；返回是否真正结算（false 表示重复结算被幂等忽略，INV-09）。
func settle_success(state: RunState, profile: PlayerProfile) -> bool:
	return false


## 执行一次失败结算；返回是否真正结算（INV-09）。
func settle_failure(state: RunState, profile: PlayerProfile) -> bool:
	return false


## 结算是否已完成。
func is_settled(state: RunState) -> bool:
	return false
