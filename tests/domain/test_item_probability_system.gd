## test_item_probability_system.gd —— FullHaul 领域测试：物品概率系统（GdUnit4）
##
## 职责：
##   覆盖搜索系统子系统「物品概率系统」（ItemProbabilitySystem）：
##   - 固定种子确定性（同种子同序列，测试可复现）
##   - 品质权重：非空表全权控制（未列出品质权重 0 被排除）
##   - 类型（category）权重分层
##   - 品质 × 类型乘积权重
##   - 空表均匀分布 / 空池返回 null
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_item_probability_system.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 构造测试定义（rarity/category/尺寸可配）
func _def(id: String, rarity: String, category: String) -> ItemDefinition:
	var def := ItemDefinition.new(id, id, rarity, 1, 1, 10)
	def.category = category
	return def


## [ItemProbabilitySystem] 固定种子：同种子抽取序列完全一致（测试确定性）
func test_seeded_rng_is_deterministic() -> void:
	var pool: Array = [_def("a", "common", "tool"), _def("b", "rare", "food")]
	var sys_a := ItemProbabilitySystem.new(42)
	var sys_b := ItemProbabilitySystem.new(42)
	for i in 20:
		var pa: ItemDefinition = sys_a.pick(pool)
		var pb: ItemDefinition = sys_b.pick(pool)
		assert_that(pa).is_not_null()
		assert_str(pa.definition_id).is_equal(pb.definition_id)


## [ItemProbabilitySystem] 品质权重归零排除：非空权重表中未列出的品质不出现
func test_rarity_zero_weight_excludes_entry() -> void:
	var common := _def("c1", "common", "tool")
	var legendary := _def("l1", "legendary", "tool")
	var pool: Array = [common, legendary]
	var sys := ItemProbabilitySystem.new(7)
	for i in 30:
		var picked: ItemDefinition = sys.pick(pool, {"legendary": 1.0})
		assert_that(picked).is_not_null()
		assert_str(picked.definition_id).is_equal("l1")


## [ItemProbabilitySystem] 类型权重分层：同品质下按 category 加权
func test_category_weights_shift_distribution() -> void:
	var tool_item := _def("t1", "common", "tool")
	var food_item := _def("f1", "common", "food")
	var pool: Array = [tool_item, food_item]
	var sys := ItemProbabilitySystem.new(11)
	var tool_count := 0
	for i in 60:
		var picked: ItemDefinition = sys.pick(pool, {}, {"tool": 9.0, "food": 1.0})
		if picked.definition_id == "t1":
			tool_count += 1
	# 权重 9:1 下 60 次全抽 tool 概率趋近 1，放宽为压倒性多数
	assert_int(tool_count).is_greater(50)


## [ItemProbabilitySystem] 品质 × 类型乘积权重
func test_rarity_times_category_weight() -> void:
	var rare_tool := _def("rt", "rare", "tool")
	var common_food := _def("cf", "common", "food")
	var pool: Array = [rare_tool, common_food]
	var sys := ItemProbabilitySystem.new(3)
	# rare_tool 权重 = 1×1 = 1；common_food 权重 = 0.2×0 = 0 -> 全抽 rare_tool
	for i in 20:
		var picked: ItemDefinition = sys.pick(pool, {"rare": 1.0, "common": 0.2},
			{"food": 0.0, "tool": 1.0})
		assert_str(picked.definition_id).is_equal("rt")


## [ItemProbabilitySystem] 空权重表均匀分布：两候选都会出现
func test_empty_weights_uniform() -> void:
	var a := _def("a", "common", "tool")
	var b := _def("b", "common", "food")
	var pool: Array = [a, b]
	var sys := ItemProbabilitySystem.new(5)
	var seen := {}
	for i in 60:
		var picked: ItemDefinition = sys.pick(pool)
		seen[picked.definition_id] = true
	assert_int(seen.size()).is_equal(2)


## [ItemProbabilitySystem] 空池 / 全零权重返回 null
func test_empty_pool_or_all_zero_returns_null() -> void:
	var sys := ItemProbabilitySystem.new(1)
	assert_that(sys.pick([], {"common": 1.0})).is_null()
	var pool: Array = [_def("a", "common", "tool")]
	assert_that(sys.pick(pool, {"common": 0.0})).is_null()
