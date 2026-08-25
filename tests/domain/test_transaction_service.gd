## test_transaction_service.gd —— FullHaul 领域测试：Transaction 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 3 落地的 TransactionService（架构 §1.1
##   Economy / Transaction 域、§3 接口原则）。
##
## 覆盖映射：
##   - INV-12 货币守恒：扣款/加款后余额与事务流水一致
##   - 原子性：余额变动与事务记录要么同时发生，要么都不发生
##   - 防重：同 profile+type+ref 重复事务被拒绝，余额不被重复扣款
##   - 余额不足：拒绝扣款且不产生流水
##   - 参数校验：空 ref_id / 空 type 拒绝
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_transaction_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 构造被测服务：内存后端事务流水 + 默认 local 账户。
func _service() -> TransactionService:
	var store := InMemoryDataStore.new()
	return TransactionService.new(MemoryRunResultRepository.new(store))


## [TransactionService] 扣款：余额正确扣减且写入流水（INV-12）
func test_deduct_records_and_balances() -> void:
	var svc := _service()
	var profile := PlayerProfile.new(1000)

	assert_that(svc.apply_transaction(profile, "purchase", -300, "backpack_4x4")).is_true()
	assert_that(profile.currency).is_equal(700)
	assert_that(svc.has_transaction("purchase", "backpack_4x4")).is_true()


## [TransactionService] 防重：同 type+ref 重复事务被拒绝，余额只扣一次（INV-12）
func test_dedupe_blocks_second_charge() -> void:
	var svc := _service()
	var profile := PlayerProfile.new(1000)

	assert_that(svc.apply_transaction(profile, "purchase", -300, "backpack_4x4")).is_true()
	assert_that(svc.apply_transaction(profile, "purchase", -300, "backpack_4x4")).is_false()
	assert_that(profile.currency).is_equal(700)


## [TransactionService] 余额不足：拒绝扣款，不产生余额变动与流水
func test_insufficient_funds_rejected() -> void:
	var svc := _service()
	var profile := PlayerProfile.new(100)

	assert_that(svc.apply_transaction(profile, "purchase", -200, "backpack_5x5")).is_false()
	assert_that(profile.currency).is_equal(100)
	assert_that(svc.has_transaction("purchase", "backpack_5x5")).is_false()


## [TransactionService] 加款（出售/结算入账）：余额增加并记录流水
func test_credit_adds_and_records() -> void:
	var svc := _service()
	var profile := PlayerProfile.new(1000)

	assert_that(svc.apply_transaction(profile, "sell", 500, "item-1")).is_true()
	assert_that(profile.currency).is_equal(1500)
	assert_that(svc.has_transaction("sell", "item-1")).is_true()


## [TransactionService] 参数校验：空 type / 空 ref_id 拒绝
func test_invalid_params_rejected() -> void:
	var svc := _service()
	var profile := PlayerProfile.new(1000)

	assert_that(svc.apply_transaction(profile, "", -100, "x")).is_false()
	assert_that(svc.apply_transaction(profile, "purchase", -100, "")).is_false()
	assert_that(profile.currency).is_equal(1000)


## [TransactionService] 原子性：失败路径（重复/余额不足）后余额与流水均无残留
func test_failed_paths_leave_no_trace() -> void:
	var store := InMemoryDataStore.new()
	var repo := MemoryRunResultRepository.new(store)
	var svc := TransactionService.new(repo)
	var profile := PlayerProfile.new(500)

	## 余额不足失败：无流水无扣款
	assert_that(svc.apply_transaction(profile, "purchase", -600, "bp")).is_false()
	assert_that(profile.currency).is_equal(500)
	assert_that(repo.has_transaction("local", "purchase", "bp")).is_false()

	## 成功后再重复：第二次失败且不二次扣款
	assert_that(svc.apply_transaction(profile, "purchase", -300, "bp")).is_true()
	assert_that(profile.currency).is_equal(200)
	assert_that(svc.apply_transaction(profile, "purchase", -300, "bp")).is_false()
	assert_that(profile.currency).is_equal(200)