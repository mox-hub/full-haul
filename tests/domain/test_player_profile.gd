## test_player_profile.gd —— FullHaul 地基测试：局外账户模型（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §5 PlayerProfile / §1.1 Profile 域。
##
## 覆盖映射：
##   - INV-12 货币守恒：change_currency 正确增减余额
##   - INV-13 局外状态与局内临时状态分离：Profile 只承载局外账本
##   - AC-21 入场货币校验：can_afford
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_player_profile.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [PlayerProfile] 货币账本：增减与余额（INV-12）
func test_currency_ledger() -> void:
	var profile := PlayerProfile.new(1000)
	assert_that(profile.currency).is_equal(1000)
	profile.change_currency(-250)
	assert_that(profile.currency).is_equal(750)
	profile.change_currency(500)
	assert_that(profile.currency).is_equal(1250)


## [PlayerProfile] 支付能力校验（AC-21）
func test_can_afford() -> void:
	var profile := PlayerProfile.new(1000)
	assert_that(profile.can_afford(1000)).is_true()
	assert_that(profile.can_afford(1001)).is_false()
	assert_that(profile.can_afford(0)).is_true()


## [PlayerProfile] 局外字段：仓库与背包装载引用（INV-13）
func test_out_of_run_fields() -> void:
	var profile := PlayerProfile.new()
	profile.warehouse_item_ids = ["w-1", "w-2"]
	profile.selected_backpack_offer_id = "backpack_5x5"
	assert_that(profile.warehouse_item_ids).contains_exactly(["w-1", "w-2"])
	assert_that(profile.selected_backpack_offer_id).is_equal("backpack_5x5")
