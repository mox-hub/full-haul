## transaction_service.gd —— FullHaul 领域服务：Economy / Transaction（经济/事务）域
##
## 职责：
##   实现 ITransactionService 契约（架构 §1.1 Economy / Transaction 域、§3 接口原则）。
##   把「货币变动」收敛为唯一入口：购买扣款/出售加款/结算入账都必须经本服务完成，
##   保证原子性与防重（INV-12），并留下可诊断的事务流水。
##
## 原子性约定（切片 3）：
##   1. 先做防重校验与余额校验；
##   2. 先写入事务流水（IRunResultRepository.insert_transaction，同 profile+type+ref
##      唯一，INV-12 防重），写入失败则整体不生效；
##   3. 事务写入成功后才改动 PlayerProfile 余额——余额变动与事务记录要么同时发生，
##      要么都不发生，领域内不出现「扣款成功但无流水」或「有流水未扣款」。
##
## 边界：
##   - V0.1 单机单账户，默认 profile_id = "local"（与 db/schema.sql 一致）。
##   - 领域层只依赖 IRunResultRepository 语义（鸭子类型），不感知具体后端。
##   - 本服务只承载账本事务，不承载局内运行态（审核 P1-3）。

extends ITransactionService
class_name TransactionService
## 本类继承领域接口 ITransactionService（本文件为切片 3 的落地实现）。

const DEFAULT_PROFILE_ID := "local"

## 事务流水仓储（IRunResultRepository 语义：insert_transaction / has_transaction）
var _tx_repo = null
## 账户 id（V0.1 单机单账户）
var _profile_id := DEFAULT_PROFILE_ID


func _init(tx_repo, profile_id := DEFAULT_PROFILE_ID) -> void:
	_tx_repo = tx_repo
	_profile_id = profile_id


## 执行一次货币变动事务（扣款用负 delta，加款用正 delta；INV-12）。
## 返回是否成功：余额不足 / 参数不合法 / 同 profile+type+ref 重复事务均失败，
## 失败时不产生任何余额变动与流水。
func apply_transaction(profile: PlayerProfile, type: String, amount: int, ref_id: String = "") -> bool:
	if profile == null or _tx_repo == null:
		return false
	if type == "" or ref_id == "":
		return false
	## 防重：同一业务引用（如 offer_id）的同类型事务只允许发生一次（INV-12）
	if _tx_repo.has_transaction(_profile_id, type, ref_id):
		return false
	var balance_before := profile.currency
	if balance_before + amount < 0:
		## 余额不足，拒绝扣款
		return false
	var balance_after := balance_before + amount
	var ok: bool = _tx_repo.insert_transaction({
		"transaction_id": "%s-%s-%s" % [_profile_id, type, ref_id],
		"profile_id": _profile_id,
		"type": type,
		"amount": amount,
		"ref_id": ref_id,
		"balance_before": balance_before,
		"balance_after": balance_after,
		"status": "ok",
	})
	if not ok:
		## 流水写入失败（如重复事务被后端拒绝）：余额不变
		return false
	profile.change_currency(amount)
	return true


## 是否已存在同 type+ref 的事务（防重查询，INV-12）。
func has_transaction(type: String, ref_id: String) -> bool:
	return _tx_repo != null and _tx_repo.has_transaction(_profile_id, type, ref_id)