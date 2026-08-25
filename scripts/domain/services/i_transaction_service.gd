## i_transaction_service.gd —— FullHaul 领域接口：Economy / Transaction（经济/事务）域
##
## 职责：
##   定义货币事务域对应用编排层暴露的最小契约（架构 §1.1 Economy / Transaction
##   域）。领域层只依赖本接口。
##
## 覆盖范围（规范 INV-12，切片 3/8）：
##   - 货币变动（购买扣款/出售加款/结算）原子化
##   - 事务防重与诊断（幂等）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 3/8）落地。

extends RefCounted
class_name ITransactionService

## 执行一次货币变动事务（扣款用负 delta）。
## 返回是否成功（余额不足/重复事务则失败，INV-12）。
func apply_transaction(profile: PlayerProfile, type: String, amount: int) -> bool:
	return false


## 查询某类型事务是否已发生（防重）。
func has_transaction(type: String, ref_id: String) -> bool:
	return false
