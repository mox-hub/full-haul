## loadout_service.gd —— FullHaul 领域服务：Loadout（入场装载）域
##
## 职责：
##   实现 ILoadoutService 契约（架构 §1.1 Loadout 域、§3 接口原则）。
##   承载入场装载的「购买 / 选择 / 扣款 / 确认绑定」用例（规范 AC-02、切片 3）：
##   - 读取背包档位（BackpackOffer，数据驱动单一来源 INV-16）
##   - 货币校验（can_afford）
##   - 购买并扣款：扣款必须走 Transaction 域保证原子性（INV-12）
##   - 确认装载：校验档位有效且已购买成功，绑定本局背包（AC-03 前置）
##
## 设计要点：
##   1. 扣款通过注入的 ITransactionService 完成，本服务不直接改余额；
##      货币守恒由 Transaction 域的防重与流水保证（INV-12）。
##   2. 领域事件（BACKPACK_PURCHASED / CURRENCY_CHANGED）经注入的 IEventBus 发布，
##      供表现层/遥测订阅；领域层不依赖 Autoload 节点（架构原则 2）。
##   3. 域间通过接口注入，不直接持有对方实例（架构原则 3）。

extends ILoadoutService
class_name LoadoutService
## 本类继承领域接口 ILoadoutService（本文件为切片 3 的落地实现）。

## 事务类型：背包购买
const TX_PURCHASE := "purchase"

## 注入的配置加载器（BackpackOffer 单一来源 INV-16）
var _config_loader: IConfigLoader = null
## 注入的事务服务（扣款原子性，INV-12）
var _transaction_service: ITransactionService = null
## 注入的事件总线（领域事件发布）
var _bus: IEventBus = null


func _init(config_loader: IConfigLoader, transaction_service: ITransactionService,
		bus: IEventBus) -> void:
	_config_loader = config_loader
	_transaction_service = transaction_service
	_bus = bus


## 查看指定背包装载档位配置；不存在返回空 Dictionary。
func get_backpack_offer(offer_id: String) -> Dictionary:
	var cfg := _config_loader.get_config() if _config_loader != null else null
	if cfg == null:
		return {}
	return cfg.get_backpack_offer(offer_id)


## 校验当前是否足以支付指定档位价格（AC-21）。
func can_afford(profile: PlayerProfile, offer_id: String) -> bool:
	if profile == null:
		return false
	var offer := get_backpack_offer(offer_id)
	if offer.is_empty():
		return false
	return profile.can_afford(offer.get("price", 0))


## 购买/选择指定背包并完成货币扣款（INV-12）。
## ref_id 为事务防重引用（默认 offer_id）：入场购买按规范 AC-02「每次确认
## 入场校验价格、正确扣款」，传 run_id 作 ref_id 使同一档位跨局可重复购买、
## 同局重复确认被 Transaction 域防重拦截。
## 返回是否成功：档位不存在 / 余额不足 / 重复购买均失败，失败时不产生任何变动。
## 成功时：
##   - 经 Transaction 域原子扣款并记录事务流水；
##   - 在档案上记录已选背包 offerId；
##   - 发布 BACKPACK_PURCHASED 与 CURRENCY_CHANGED 事件。
func purchase_backpack(profile: PlayerProfile, offer_id: String, ref_id: String = "") -> bool:
	if profile == null or _transaction_service == null:
		return false
	var offer := get_backpack_offer(offer_id)
	if offer.is_empty():
		return false
	var tx_ref := ref_id if ref_id != "" else offer_id
	var price: int = offer.get("price", 0)
	var balance_before := profile.currency
	## 扣款必须走 Transaction 域（原子 + 防重，INV-12）
	if not _transaction_service.apply_transaction(profile, TX_PURCHASE, -price, tx_ref):
		return false
	profile.selected_backpack_offer_id = offer_id
	if _bus != null:
		_bus.publish(DomainEvents.Events.BACKPACK_PURCHASED, DomainEvents.BackpackPurchased.new(
			offer_id, price, balance_before, profile.currency))
		_bus.publish(DomainEvents.Events.CURRENCY_CHANGED, DomainEvents.CurrencyChanged.new(
			-price, balance_before, profile.currency))
	return true


## 确认装载并绑定本局背包（AC-03 前置校验）。
## ref_id 为购买事务引用（默认 offer_id，须与 purchase_backpack 使用的引用一致）。
## 返回是否成功：档位有效且该档位已完成购买（存在 purchase 事务）才允许确认。
## 说明：本局背包的格子尺寸绑定由 Item & Inventory 域（切片 5）落地；
## 本切片只保证「确认时该档位已购得、可带入本局」。
func confirm_loadout(run: RunState, offer_id: String, ref_id: String = "") -> bool:
	if run == null:
		return false
	if get_backpack_offer(offer_id).is_empty():
		return false
	var tx_ref := ref_id if ref_id != "" else offer_id
	if _transaction_service == null \
			or not _transaction_service.has_transaction(TX_PURCHASE, tx_ref):
		return false
	return true