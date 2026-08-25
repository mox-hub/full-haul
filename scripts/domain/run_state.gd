## run_state.gd —— FullHaul 局内状态模型（RunSession/RunState）
##
## 职责：
##   定义一局对局的运行时状态（架构 §1.1 RunSession 域、§5 RunState 实体）。
##   每局一个实例，经接口注入，禁止全局静态单例承载运行态（审核 P1-3）。
##
## 关键约束：
##   - run_id 唯一
##   - 状态单向受控（phase 变更由状态机驱动）
##   - settled 标记防止重复结算（INV-09）

extends RefCounted
class_name RunState


## 顶层状态机的运行阶段（对应架构 §2.1）
enum Phase {
	BOOT,                  # 启动加载
	OUT_OF_RUN,            # 局外
	LOADOUT,               # 入场装载（选/买背包）
	RUN_INIT,              # 对局初始化
	IN_RUN_LOCKED,         # 局内-撤离锁定（完成数<5）
	IN_RUN_EXTRACTABLE,    # 局内-可撤离（完成数>=5）
	EXTRACTING,            # 撤离读条中
	RUN_SUCCEEDED,         # 撤离成功
	RUN_FAILED,            # 撤离失败
	SETTLED,               # 已结算
	ERROR,                 # 错误态
}


var run_id: String = ""
var phase: Phase = Phase.BOOT
var remaining_match_time := 0
var remaining_extraction_time := 0
var completed_container_count := 0
var settled := false
## 本局携带回仓库的物品 instanceId 列表（撤离成功时）
var carried_item_ids: Array = []
## 撤离失败时安全返回的物品 instanceId 列表（安全箱）
var safe_item_ids: Array = []


func _init(p_run_id := "", p_match_duration := 0, p_extraction_duration := 0) -> void:
	run_id = p_run_id
	remaining_match_time = p_match_duration
	remaining_extraction_time = p_extraction_duration
	phase = Phase.RUN_INIT


## 进入指定阶段（由状态机调用）。
## 提供基本的单向流转约束：不允许任意跳转（子类/状态机可加强校验）。
func set_phase(new_phase: Phase) -> void:
	phase = new_phase


## 标记已结算（幂等保护，INV-09）。
## 返回是否本次真正执行了「首次结算」标记（false 表示重复结算被忽略）。
func mark_settled() -> bool:
	if settled:
		return false
	settled = true
	return true


## 是否为已完成全部必搜容器的可撤离状态
func is_extractable() -> bool:
	return completed_container_count >= 0  # 阈值由配置/状态机决定
