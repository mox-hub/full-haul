## test_game_config.gd —— FullHaul 地基测试：全局配置单一来源（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §5 GameConfig / §6 配置单一来源（规范 6.1/6.2）。
##
## 覆盖映射：
##   - INV-16 配置单一来源：核心数值均来自配置，校验可通过
##   - AC-16/20/21/22 配置驱动：品质揭晓耗时、背包档位、安全箱
##   - 数值范围：V0.1 最小语义实体（match/extraction/required/initial）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_game_config.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [GameConfig] 核心数值为 V0.1 最小语义实体基线（架构 §5）
func test_core_values() -> void:
	var cfg := GameConfig.new()
	assert_that(cfg.match_duration).is_equal(180)
	assert_that(cfg.extraction_duration).is_equal(15)
	assert_that(cfg.required_completed_containers).is_equal(5)
	assert_that(cfg.initial_currency).is_equal(100000)


## [GameConfig] 品质 -> 揭晓耗时映射（AC-16）
func test_reveal_durations() -> void:
	var cfg := GameConfig.new()
	assert_that(cfg.get_reveal_duration("common")).is_equal(0.5)
	assert_that(cfg.get_reveal_duration("uncommon")).is_equal(1.0)
	assert_that(cfg.get_reveal_duration("rare")).is_equal(2.0)
	assert_that(cfg.get_reveal_duration("epic")).is_equal(3.0)
	assert_that(cfg.get_reveal_duration("legendary")).is_equal(5.0)
	## 未知品质回退默认 1.0
	assert_that(cfg.get_reveal_duration("unknown")).is_equal(1.0)


## [GameConfig] 背包三档配置（架构 §5 BackpackOffer）
func test_backpack_offers() -> void:
	var cfg := GameConfig.new()
	assert_that(cfg.backpack_offers.size()).is_equal(3)
	assert_that(cfg.backpack_offers["backpack_4x4"]["price"]).is_equal(1000)
	assert_that(cfg.backpack_offers["backpack_5x5"]["price"]).is_equal(2500)
	assert_that(cfg.backpack_offers["backpack_6x6"]["price"]).is_equal(5000)
	## 不存在的档位返回空字典
	assert_that(cfg.get_backpack_offer("nope").is_empty()).is_true()


## [GameConfig] 安全箱配置（架构 §5 SafeContainerConfig）
func test_safe_container() -> void:
	var cfg := GameConfig.new()
	assert_that(cfg.safe_container["grid_width"]).is_equal(2)
	assert_that(cfg.safe_container["grid_height"]).is_equal(2)
	assert_that(cfg.safe_container["default_owned"]).is_true()


## [GameConfig] 校验：默认配置应通过（INV-16 单一来源合法性）
func test_validate_passes() -> void:
	var cfg := GameConfig.new()
	assert_that(cfg.validate().is_empty()).is_true()


## [GameConfig] 校验：非法值应被检出（不硬编码、配置驱动）
func test_validate_catches_invalid() -> void:
	var cfg := GameConfig.new()
	cfg.match_duration = 0
	cfg.backpack_offers["backpack_4x4"]["price"] = 0
	var errors: Array = cfg.validate()
	assert_that(errors.is_empty()).is_false()
	assert_that(errors.size()).is_greater_equal(2)
