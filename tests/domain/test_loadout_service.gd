## test_loadout_service.gd —— FullHaul 领域测试：Loadout 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 3 落地的 LoadoutService（架构 §1.1 Loadout 域）。
##
## 覆盖映射：
##   - AC-02 / AC-21：背包档位查看、货币校验、购买扣款
##   - INV-12：扣款必须走 Transaction 域（原子 + 防重，不重复扣款）
##   - 事件流：购买成功后发布 BACKPACK_PURCHASED / CURRENCY_CHANGED
##   - 确认装载：未购买 / 档位不存在的背包不允许确认（AC-03 前置）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_loadout_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 假事件总线：记录发布的事件 id 与 payload
class _FakeEventBus:
	extends IEventBus
	var published: Array = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append({"event": event_id, "payload": payload})

	func has_published(event_id: int) -> bool:
		for entry in published:
			if entry.get("event", -1) == event_id:
				return true
		return false

	func last_payload(event_id: int):
		for i in range(published.size() - 1, -1, -1):
			if published[i].get("event", -1) == event_id:
				return published[i].get("payload", null)
		return null


## 假配置加载器：返回默认 GameConfig（含三档背包，INV-16）
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


## 组装被测 LoadoutService：内存事务后端 + 假总线。
func _service() -> Dictionary:
	var store := InMemoryDataStore.new()
	var bus := _FakeEventBus.new()
	var tx := TransactionService.new(MemoryRunResultRepository.new(store))
	var svc := LoadoutService.new(_FakeConfigLoader.new(), tx, bus)
	return {"svc": svc, "tx": tx, "bus": bus, "store": store}


## [LoadoutService] 背包档位查看（数据驱动单一来源 INV-16）
func test_get_backpack_offer() -> void:
	var svc: LoadoutService = _service()["svc"]
	assert_that(svc.get_backpack_offer("backpack_4x4").get("price")).is_equal(1000)
	assert_that(svc.get_backpack_offer("backpack_6x6").get("grid_width")).is_equal(6)
	assert_that(svc.get_backpack_offer("nope").is_empty()).is_true()


## [LoadoutService] 货币校验（AC-21）
func test_can_afford() -> void:
	var svc: LoadoutService = _service()["svc"]
	var profile := PlayerProfile.new(1000)
	assert_that(svc.can_afford(profile, "backpack_4x4")).is_true()
	assert_that(svc.can_afford(profile, "backpack_5x5")).is_false()
	assert_that(svc.can_afford(profile, "nope")).is_false()


## [LoadoutService] 购买成功：扣款走 Transaction、记录选择、发布事件（AC-02/INV-12）
func test_purchase_success() -> void:
	var parts := _service()
	var svc: LoadoutService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]
	var profile := PlayerProfile.new(100000)

	assert_that(svc.purchase_backpack(profile, "backpack_4x4")).is_true()
	assert_that(profile.currency).is_equal(99000)
	assert_that(profile.selected_backpack_offer_id).is_equal("backpack_4x4")
	assert_that(parts["tx"].has_transaction("purchase", "backpack_4x4")).is_true()

	## 事件：BACKPACK_PURCHASED（含价格与前后余额）+ CURRENCY_CHANGED
	assert_that(bus.has_published(DomainEvents.Events.BACKPACK_PURCHASED)).is_true()
	var bp: DomainEvents.BackpackPurchased = bus.last_payload(DomainEvents.Events.BACKPACK_PURCHASED)
	assert_that(bp.offer_id).is_equal("backpack_4x4")
	assert_that(bp.price).is_equal(1000)
	assert_that(bp.balance_before).is_equal(100000)
	assert_that(bp.balance_after).is_equal(99000)
	var cc: DomainEvents.CurrencyChanged = bus.last_payload(DomainEvents.Events.CURRENCY_CHANGED)
	assert_that(cc.delta).is_equal(-1000)
	assert_that(cc.balance_before).is_equal(100000)
	assert_that(cc.balance_after).is_equal(99000)


## [LoadoutService] 余额不足：购买失败，不扣款、不记录选择、不发事件
func test_purchase_insufficient() -> void:
	var parts := _service()
	var svc: LoadoutService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]
	var profile := PlayerProfile.new(500)

	assert_that(svc.purchase_backpack(profile, "backpack_4x4")).is_false()
	assert_that(profile.currency).is_equal(500)
	assert_that(profile.selected_backpack_offer_id).is_equal("")
	assert_that(parts["tx"].has_transaction("purchase", "backpack_4x4")).is_false()
	assert_that(bus.has_published(DomainEvents.Events.BACKPACK_PURCHASED)).is_false()
	assert_that(bus.has_published(DomainEvents.Events.CURRENCY_CHANGED)).is_false()


## [LoadoutService] 档位不存在：购买失败
func test_purchase_unknown_offer() -> void:
	var svc: LoadoutService = _service()["svc"]
	var profile := PlayerProfile.new(100000)
	assert_that(svc.purchase_backpack(profile, "nope")).is_false()
	assert_that(profile.currency).is_equal(100000)


## [LoadoutService] 防重：同一档位重复购买不重复扣款（INV-12）
func test_purchase_dedupe_no_double_charge() -> void:
	var svc: LoadoutService = _service()["svc"]
	var profile := PlayerProfile.new(100000)

	assert_that(svc.purchase_backpack(profile, "backpack_5x5")).is_true()
	assert_that(svc.purchase_backpack(profile, "backpack_5x5")).is_false()
	assert_that(profile.currency).is_equal(97500)
	assert_that(profile.selected_backpack_offer_id).is_equal("backpack_5x5")


## [LoadoutService] 确认装载：已购档位可确认；未购/不存在档位拒绝（AC-03 前置）
func test_confirm_loadout() -> void:
	var parts := _service()
	var svc: LoadoutService = parts["svc"]
	var profile := PlayerProfile.new(100000)
	var run := RunState.new("run-1", 180, 15)

	## 未购买：不允许确认
	assert_that(svc.confirm_loadout(run, "backpack_4x4")).is_false()
	## 档位不存在：不允许确认
	assert_that(svc.confirm_loadout(run, "nope")).is_false()

	## 购买后：可确认（绑定本局背包）
	assert_that(svc.purchase_backpack(profile, "backpack_4x4")).is_true()
	assert_that(svc.confirm_loadout(run, "backpack_4x4")).is_true()