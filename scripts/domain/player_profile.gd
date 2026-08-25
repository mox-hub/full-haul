## player_profile.gd —— FullHaul 局外账户模型（Profile/Player）
##
## 职责：
##   定义局外账户的运行时状态（架构 §1.1 Profile 域、§5 PlayerProfile 实体）。
##   承载货币账本、仓库物品、已选背包装载引用。
##
## 范围约束：
##   局外状态与局内临时状态分离（INV-13）；不包含生死/属性等未来域内容。

extends RefCounted
class_name PlayerProfile


var currency := 0
## 仓库中的物品 instanceId 列表
var warehouse_item_ids: Array = []
## 已选定的入场背包 offerId（Loadout）
var selected_backpack_offer_id: String = ""


func _init(p_currency := 0) -> void:
	currency = p_currency


## 增减货币（返回变更后的余额）。
## 注意：实际扣款/加款的原子性与防重由 Transaction 域处理，这里仅做账本操作。
func change_currency(delta: int) -> int:
	currency += delta
	return currency


## 是否足以支付 price
func can_afford(price: int) -> bool:
	return currency >= price
