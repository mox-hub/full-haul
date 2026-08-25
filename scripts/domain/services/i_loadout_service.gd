## i_loadout_service.gd —— FullHaul 领域接口：Loadout（入场装载）域
##
## 职责：
##   定义入场装载域对应用编排层暴露的最小契约（架构 §1.1 Loadout 域、
##   §3 接口原则）。领域层只依赖本接口，不依赖任何 Godot 节点。
##
## 覆盖范围（规范 AC-02，切片 3）：
##   - 查看/选择背包装载（BackpackOffer）
##   - 货币校验与扣款（经 Transaction 域，INV-12）
##   - 确认后绑定本局背包并推进顶层状态机到 RUN_INIT
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 3）落地。

extends RefCounted
class_name ILoadoutService

## 查看指定背包装载档位配置；不存在返回空 Dictionary。
func get_backpack_offer(offer_id: String) -> Dictionary:
	return {}


## 购买/选择指定背包并完成货币扣款（INV-12）。
## 返回是否成功（余额不足/不存在则失败，不产生事务）。
func purchase_backpack(profile: PlayerProfile, offer_id: String) -> bool:
	return false


## 校验当前是否足以支付指定档位价格。
func can_afford(profile: PlayerProfile, offer_id: String) -> bool:
	return false


## 确认装载并绑定本局背包，返回是否成功。
## 成功后由顶层状态机进入 RUN_INIT（AC-03）。
func confirm_loadout(run: RunState, offer_id: String) -> bool:
	return false
